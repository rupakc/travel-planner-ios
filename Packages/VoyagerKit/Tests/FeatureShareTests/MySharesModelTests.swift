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
struct MySharesModelTests {
    final class Events {
        var all: [TelemetryEvent] = []

        var revokes: [String] {
            all.compactMap { if case .shareRevoke(let kind) = $0 { kind } else { nil } }
        }

        var copies: [String] {
            all.compactMap { if case .shareAction(let kind, "copy") = $0 { kind } else { nil } }
        }
    }

    final class Copied {
        var texts: [String] = []
        var succeeds = true
    }

    private struct Rig {
        let model: MySharesModel
        let fakes: FakeRepositories
        let env: AppEnvironment
        let router: RecordingRouter
        let events: Events
        let copied: Copied
    }

    private func share(_ token: String, kind: ShareKind = .plan, title: String = "Lisbon", plan: Int? = 3, at created: String? = nil) -> Share {
        Share(
            token: token, kind: kind, planID: plan, title: title, url: "https://fake.voyager.test/share/\(token)",
            options: ShareOptions(dates: .month), createdAt: created)
    }

    private func rig(sharing: Int = 1, configure: (FakeRepositories) -> Void = { _ in }) -> Rig {
        let fakes = FakeRepositories()
        configure(fakes)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["sharing": .number(Double(sharing))]))
        let router = RecordingRouter()
        env.router = router
        let events = Events()
        let copied = Copied()
        let model = MySharesModel(
            env: env,
            pasteboard: { text in
                copied.texts.append(text)
                return copied.succeeds
            },
            track: { events.all.append($0) })
        return Rig(model: model, fakes: fakes, env: env, router: router, events: events, copied: copied)
    }

    // MARK: List

    @Test func test_legacyRowsListed() async {
        let r = rig {
            $0.shares.onList.returns(
                ShareList(
                    shares: [self.share("newtoken1")],
                    legacyPlanShares: [LegacyPlanShare(planID: 7, name: "Old Rome", url: "https://fake.voyager.test/share/legacytok7")]))
        }
        await r.model.load()
        #expect(r.model.phase == .loaded)
        #expect(r.model.shares.map(\.token) == ["newtoken1"])
        #expect(r.model.legacy.count == 1 && r.model.legacy[0].title == "Old Rome" && r.model.legacy[0].planID == 7)
        #expect(r.model.legacy[0].source == .legacy && r.model.legacy[0].token == "legacytok7")
        #expect(r.model.legacy[0].target == ShareTarget.plan(id: 7))
    }

    @Test func test_newestFirst() async {
        let r = rig {
            $0.shares.onList.returns(
                ShareList(shares: [
                    self.share("older001", at: "2026-10-01T10:00:00Z"), self.share("newest01", at: "2026-11-10T10:00:00.250Z"),
                    self.share("nodate01"),
                ]))
        }
        await r.model.load()
        #expect(r.model.shares.map(\.token) == ["newest01", "older001", "nodate01"])
    }

    @Test func test_listEmptyAndError() async {
        let r = rig()
        await r.model.load()
        #expect(r.model.phase == .loaded && r.model.isEmpty)
        r.fakes.shares.onList.fails(APIError.rateLimited(message: "Slow down, try in 4 minutes.", retryAfter: 240))
        await r.model.load()
        #expect(r.model.phase == .failed(kind: .rateLimited, detail: "Slow down, try in 4 minutes."))
        // Retry works.
        r.fakes.shares.onList.returns(ShareList(shares: [share("afterretry")]))
        await r.model.load()
        #expect(r.model.phase == .loaded && r.model.shares.count == 1)
    }

    @Test func test_flagOffIsUnavailableAndCallsNothing() async {
        let r = rig(sharing: 0)
        await r.model.load()
        #expect(r.model.phase == .unavailable)
        #expect(r.fakes.shares.onList.callCount == 0)
    }

    @Test func test_sharingDisabled404ShowsUnavailable() async {
        let r = rig { $0.shares.onList.fails(APIError.notFound("Sharing is not available.")) }
        await r.model.load()
        #expect(r.model.phase == .unavailable)
    }

    // MARK: Revoke

    @Test func test_revokeRemovesImmediately() async {
        let r = rig { $0.shares.onList.returns(ShareList(shares: [self.share("keep0001"), self.share("gone0001", kind: .recap)])) }
        await r.model.load()
        let gone = r.model.shares[1]
        r.model.askRevoke(gone)
        #expect(r.model.confirming == gone.id)
        await r.model.confirmRevoke(gone)
        #expect(r.model.shares.map(\.token) == ["keep0001"])
        #expect(r.fakes.shares.onRevoke.calls == ["gone0001"])
        #expect(r.model.confirming == nil && r.model.notice == .revoked)
        #expect(r.events.revokes == ["recap"])
    }

    @Test func test_cancelKeepsTheLink() async {
        let r = rig { $0.shares.onList.returns(ShareList(shares: [self.share("keep0001")])) }
        await r.model.load()
        r.model.askRevoke(r.model.shares[0])
        r.model.cancelRevoke()
        #expect(r.model.confirming == nil && r.model.shares.count == 1 && r.fakes.shares.onRevoke.callCount == 0)
    }

    @Test func test_revokeLegacyUsesThePlanRoute() async {
        let r = rig {
            $0.shares.onList.returns(
                ShareList(legacyPlanShares: [LegacyPlanShare(planID: 7, name: "Old Rome", url: "https://fake.voyager.test/share/legacytok7")]))
        }
        await r.model.load()
        await r.model.confirmRevoke(r.model.legacy[0])
        #expect(r.fakes.shares.onRevokeLegacy.calls == [7] && r.fakes.shares.onRevoke.callCount == 0)
        #expect(r.model.legacy.isEmpty && r.events.revokes == ["plan"])
    }

    @Test func test_revoke404TreatedAsGone() async {
        let r = rig {
            $0.shares.onList.returns(ShareList(shares: [self.share("gone0001")]))
            $0.shares.onRevoke.fails(APIError.notFound("Share not found."))
        }
        await r.model.load()
        await r.model.confirmRevoke(r.model.shares[0])
        #expect(r.model.shares.isEmpty && r.model.notice == .revoked)
    }

    @Test func test_revokeFailureKeepsTheRowAndSaysSo() async {
        let r = rig {
            $0.shares.onList.returns(ShareList(shares: [self.share("stay0001")]))
            $0.shares.onRevoke.fails(APIError.network)
        }
        await r.model.load()
        await r.model.confirmRevoke(r.model.shares[0])
        #expect(r.model.shares.count == 1)
        #expect(r.model.notice == .revokeFailed(L10n.text(K.share.mine.error)))
        #expect(r.events.revokes.isEmpty)
    }

    // MARK: Copy, open, share again

    @Test func test_copyPutsTheLinkOnThePasteboard() async {
        let r = rig { $0.shares.onList.returns(ShareList(shares: [self.share("copy0001", kind: .savings, plan: nil)])) }
        await r.model.load()
        r.model.copy(r.model.shares[0])
        #expect(r.copied.texts == ["https://fake.voyager.test/share/copy0001"] && r.model.notice == .copied)
        #expect(r.events.copies == ["savings"])
        r.copied.succeeds = false
        r.model.copy(r.model.shares[0])
        #expect(r.model.notice == .copyFailed)
    }

    @Test func test_openRoutesToTheViewer() async {
        let r = rig { $0.shares.onList.returns(ShareList(shares: [self.share("open0001")])) }
        await r.model.load()
        r.model.open(r.model.shares[0])
        #expect(r.router.opened == [.openShare(token: "open0001")])
    }

    @Test func test_shareAgainOnlyForKindsTheSheetCanRebuild() async {
        let r = rig {
            $0.shares.onList.returns(
                ShareList(shares: [
                    self.share("plan0001"), self.share("recap001", kind: .recap, plan: 4), self.share("save0001", kind: .savings, plan: nil),
                    self.share("quiz0001", kind: .quiz, plan: nil), self.share("what0001", kind: .unknown("podcast"), plan: nil),
                ]))
        }
        await r.model.load()
        let targets = r.model.shares.map(\.target)
        #expect(targets == [ShareTarget.plan(id: 3), .recap(planID: 4), .savings, nil, nil])
        r.model.shareAgain(r.model.shares[0])
        #expect(r.model.sharingAgain?.token == "plan0001" && r.model.sharingAgain?.options == ShareOptions(dates: .month))
        r.model.sharingAgain = nil
        r.model.shareAgain(r.model.shares[3])
        #expect(r.model.sharingAgain == nil)
    }

    // MARK: Paste

    @Test func test_pasteRoutesToViewer() {
        let r = rig()
        r.model.paste([URL(string: "https://fake.voyager.test/share/pasted0001")!])
        #expect(r.router.opened == [.openShare(token: "pasted0001")] && !r.model.pasteInvalid)
        r.model.paste([URL(string: "voyager://share/custom0001")!])
        #expect(r.router.opened.last == .openShare(token: "custom0001"))
    }

    @Test func test_pasteRefusesAnythingElse() {
        let r = rig()
        for text in [
            "https://evil.example/share/pasted0001", "http://fake.voyager.test/share/pasted0001",
            "https://fake.voyager.test/share/short", "https://fake.voyager.test/trips/12", "https://fake.voyager.test/share/a/b",
            "voyager://import?url=https://x.test",
        ] {
            r.model.paste([URL(string: text)!])
            #expect(r.model.pasteInvalid, "\(text)")
        }
        #expect(r.router.opened.isEmpty)
        r.model.paste([])
        #expect(r.model.pasteInvalid)
    }
}
