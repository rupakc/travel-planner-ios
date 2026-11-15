import Foundation
import L10n
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureShare

@MainActor
struct ShareSheetModelTests {
    /// Events recorded by the model's telemetry sink.
    final class Events {
        var all: [TelemetryEvent] = []
    }

    private func config(sharing: Int = 1) -> ClientConfig { ClientConfig(features: ["sharing": .number(Double(sharing))]) }

    private func share(
        kind: ShareKind = .plan, options: ShareOptions = ShareOptions(), token: String = "tok1", cards: Bool = true
    ) -> Share {
        Share(
            token: token, kind: kind, planID: 3, url: "https://fake.voyager.test/share/\(token)",
            cardLinkURL: cards ? "https://fake.voyager.test/api/share/\(token)/card.png?size=link" : nil,
            cardStoryURL: cards ? "https://fake.voyager.test/api/share/\(token)/card.png?size=story" : nil,
            options: options)
    }

    private struct Rig {
        let model: ShareSheetModel
        let fakes: FakeRepositories
        let loader: FakeShareCardLoader
        let env: AppEnvironment
        let events: Events
        let copied: Copied
    }

    final class Copied {
        var texts: [String] = []
        var succeeds = true
    }

    private func rig(
        target: ShareTarget = .plan(id: 3), sharing: Int = 1, configure: (FakeRepositories) -> Void = { _ in }
    ) -> Rig {
        let fakes = FakeRepositories()
        configure(fakes)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config(sharing: sharing))
        let loader = FakeShareCardLoader()
        let events = Events()
        let copied = Copied()
        let model = ShareSheetModel(
            env: env, target: target, loader: loader,
            pasteboard: { text in
                copied.texts.append(text)
                return copied.succeeds
            },
            track: { events.all.append($0) })
        return Rig(model: model, fakes: fakes, loader: loader, env: env, events: events, copied: copied)
    }

    // MARK: Defaults and idempotence

    @Test func test_privateDefaults() async {
        let r = rig { $0.shares.onCreate.returns(self.share()) }
        #expect(r.model.options == ShareOptions())
        #expect(r.model.options.dates == .hidden && !r.model.options.showOrigin && !r.model.options.showName)
        await r.model.create()
        let sent = r.fakes.shares.onCreate.lastCall
        #expect(sent?.options == ShareOptions() && sent?.kind == .plan && sent?.planID == 3)
    }

    @Test func test_createIsIdempotentUI() async {
        let fakes = FakeRepositories()
        // The server answers the same token for the second create and replaces the options.
        fakes.shares.onCreate.handler = { request in
            Share(
                token: "same", kind: .plan, planID: 3, url: "https://fake.voyager.test/share/same",
                cardLinkURL: nil, cardStoryURL: nil, options: request.options)
        }
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        let model = ShareSheetModel(env: env, target: .plan(id: 3), loader: FakeShareCardLoader(), track: { _ in })

        #expect(model.primaryTitle == L10n.text(K.share.create) && model.canCreate && !model.hasLink)
        await model.create()
        #expect(model.share?.token == "same" && model.hasLink)
        // Nothing changed: no second create from a double tap.
        #expect(!model.canCreate)
        await model.create()
        #expect(fakes.shares.onCreate.callCount == 1)

        model.options.dates = .month
        model.options.showName = true
        #expect(model.isDirty && model.canCreate)
        #expect(model.primaryTitle == L10n.text(K.share.update))
        await model.create()
        #expect(fakes.shares.onCreate.callCount == 2)
        #expect(fakes.shares.onCreate.lastCall?.options == ShareOptions(dates: .month, showOrigin: false, showName: true))
        #expect(model.share?.token == "same" && model.share?.options.dates == .month)
        #expect(model.status == L10n.text(K.share.status.updated) && !model.isDirty)
    }

    // MARK: Kinds

    @Test func test_unknownKindIsPlainLink() async {
        let r = rig { $0.shares.onCreate.returns(Share(token: "u1", kind: .unknown("podcast"), url: "https://h/share/u1")) }
        await r.model.create()
        await r.model.settled()
        #expect(r.model.hasLink && r.model.linkURL?.absoluteString == "https://h/share/u1")
        #expect(!r.model.offersCard && r.model.shareText == nil)
        #expect(r.loader.onLoad.callCount == 0)  // no card for a kind the app does not know
        r.model.copyLink()
        #expect(r.copied.texts == ["https://h/share/u1"])
        // The registry has no value for it: no telemetry event carries a made-up kind.
        #expect(!r.events.all.contains { if case .shareAction = $0 { true } else { false } })
    }

    @Test func test_targetsSendTheirOwnFields() async {
        let quiz = rig(target: .quiz(sessionID: "s-9")) { $0.shares.onCreate.returns(self.share(kind: .quiz)) }
        await quiz.model.create()
        #expect(quiz.fakes.shares.onCreate.lastCall?.sessionID == "s-9" && quiz.fakes.shares.onCreate.lastCall?.planID == nil)
        #expect(!quiz.model.showsOptions)
        let savings = rig(target: .savings) { $0.shares.onCreate.returns(self.share(kind: .savings)) }
        await savings.model.create()
        #expect(savings.fakes.shares.onCreate.lastCall?.kind == .savings && savings.fakes.shares.onCreate.lastCall?.planID == nil)
    }

    // MARK: Cards

    @Test func test_cardsAreDownloadedAfterCreate() async {
        let r = rig { $0.shares.onCreate.returns(self.share()) }
        await r.model.create()
        #expect(r.model.linkCard == .loading && r.model.storyCard == .loading)
        await r.model.settled()
        guard case .ready = r.model.linkCard, case .ready = r.model.storyCard else {
            Issue.record("both cards should be ready")
            return
        }
        let sizes = Set(r.loader.onLoad.calls.map(\.size))
        #expect(sizes == [.link, .story] && r.loader.onLoad.calls.allSatisfy { $0.token == "tok1" })
    }

    @Test func test_downloadFailureSharesLinkOnly() async {
        let r = rig { $0.shares.onCreate.returns(self.share()) }
        r.loader.onLoad.fails(ShareCardError.untrustedHost)
        await r.model.create()
        await r.model.settled()
        #expect(r.model.linkCard == .unavailable && r.model.storyCard == .unavailable)
        // The link is still there and still shareable.
        #expect(r.model.phase == .ready && r.model.linkURL?.absoluteString == "https://fake.voyager.test/share/tok1")
        r.model.copyLink()
        #expect(r.copied.texts == ["https://fake.voyager.test/share/tok1"])
    }

    @Test func test_cardUrlsAreOptional() async {
        let r = rig { $0.shares.onCreate.returns(self.share(cards: false)) }
        await r.model.create()
        await r.model.settled()
        #expect(r.model.linkCard == .unavailable && r.loader.onLoad.callCount == 0 && r.model.hasLink)
    }

    // MARK: Flag

    @Test func test_flagOffKeepsLegacy() async {
        let r = rig(sharing: 0) { $0.plans.onShare.returns("legacytoken") }
        #expect(r.model.isLegacyOnly && !r.model.isV2 && !r.model.showsOptions)
        await r.model.create()
        #expect(r.fakes.shares.onCreate.callCount == 0)  // the v2 route is never called
        #expect(r.fakes.plans.onShare.lastCall == 3)
        #expect(r.model.linkURL?.absoluteString == "https://fake.voyager.test/share/legacytoken")
        #expect(r.model.phase == .ready && !r.model.offersCard)
    }

    @Test func test_flagOffHasNothingToShareForOtherKinds() async {
        let r = rig(target: .recap(planID: 4), sharing: 0)
        #expect(r.model.isUnavailable)
        await r.model.create()
        #expect(r.fakes.shares.onCreate.callCount == 0 && r.fakes.plans.onShare.callCount == 0)
        guard case .failed(let failure) = r.model.phase else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.message == L10n.text(K.share.errors.unavailable))
    }

    @Test func test_sharingDisabledAnswerFallsBackToLegacyForPlans() async {
        let r = rig { fakes in
            fakes.shares.onCreate.fails(APIError.notFound("Sharing is not available."))
            fakes.plans.onShare.returns("legacy2")
        }
        await r.model.create()
        #expect(r.model.linkURL?.absoluteString == "https://fake.voyager.test/share/legacy2")
        #expect(r.model.phase == .ready)
        #expect(!r.env.shares.isAvailable)
    }

    // MARK: Errors

    @Test func test_errorCodeMapping() async {
        func failure(_ error: APIError, target: ShareTarget = .recap(planID: 3)) async -> ShareSheetFailure? {
            let r = rig(target: target) { $0.shares.onCreate.fails(error) }
            await r.model.create()
            if case .failed(let failure) = r.model.phase { return failure }
            return nil
        }
        let missingPlan = await failure(.notFound("Plan not found."))
        #expect(missingPlan?.failure == .planNotFound && missingPlan?.message == L10n.text(K.share.errors.create))
        let noTrip = await failure(
            .client(status: 422, detail: "x", code: nil, body: .object(["error_code": .string("no_active_trip")])), target: .status(planID: nil))
        #expect(noTrip?.failure == .noActiveTrip && noTrip?.message == L10n.text(K.share.errors.noActiveTrip))
        let badKind = await failure(.client(status: 422, detail: nil, code: "invalid_kind", body: .null))
        #expect(badKind?.failure == .invalidKind && badKind?.message == L10n.text(K.share.errors.unavailable))
        // A 429 shows the backend's own text.
        let limited = await failure(.rateLimited(message: "Too many shares. Try again in 4 minutes.", retryAfter: 240))
        #expect(limited?.failure == nil && limited?.message == "Too many shares. Try again in 4 minutes.")
        let offline = await failure(.network)
        #expect(offline?.message == L10n.text(K.common.error.network))
    }

    @Test func test_failedCreateCanBeRetried() async {
        let r = rig { $0.shares.onCreate.fails(APIError.network) }
        await r.model.create()
        guard case .failed = r.model.phase else {
            Issue.record("expected failed")
            return
        }
        #expect(r.model.canCreate && !r.model.hasLink)
        r.fakes.shares.onCreate.returns(share())
        await r.model.create()
        #expect(r.model.phase == .ready)
    }

    // MARK: Telemetry and copy

    @Test func test_telemetry() async {
        let r = rig { $0.shares.onCreate.returns(self.share(options: ShareOptions(dates: .month))) }
        r.model.opened()
        r.model.opened()  // once
        r.model.options.dates = .month
        await r.model.create()
        r.model.copyLink()
        r.model.didShareNatively(tid: "share.native")
        var opens = 0
        var created: [String] = []
        var actions: [String] = []
        for event in r.events.all {
            switch event {
            case .shareOpen(let kind): opens += 1; #expect(kind == "plan")
            case .shareCreate(let kind, let dates): created.append("\(kind)/\(dates)")
            case .shareAction(let kind, let target): actions.append("\(kind)/\(target)")
            default: break
            }
        }
        #expect(opens == 1 && created == ["plan/month"] && actions == ["plan/copy", "plan/native"])
    }

    @Test func test_copyFailureIsSaid() async {
        let r = rig { $0.shares.onCreate.returns(self.share()) }
        r.copied.succeeds = false
        await r.model.create()
        r.model.copyLink()
        #expect(r.model.copyFailed && r.model.status == L10n.text(K.share.status.copyFailed))
        r.copied.succeeds = true
        r.model.copyLink()
        #expect(!r.model.copyFailed && r.model.status == L10n.text(K.share.status.copy))
    }
}
