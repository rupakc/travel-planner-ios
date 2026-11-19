import AuthCore
import Foundation
import L10n
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerData
import VoyagerEnv
import VoyagerModel

@testable import FeatureSocial
@testable import VoyagerEnv

@MainActor
struct IdeaFlowsTests {
    final class Events {
        var all: [TelemetryEvent] = []
    }

    private func makeEnv(
        social: Bool = true, rules: Bool = true, configure: (FakeRepositories) -> Void = { _ in }
    ) -> (AppEnvironment, FakeRepositories) {
        let fakes = FakeRepositories()
        configure(fakes)
        let features: [String: JSONValue] = social ? ["social": .number(1)] : [:]
        let env = AppEnvironment.fake(user: User(username: "sam"), fakes: fakes, clientConfig: ClientConfig(features: features))
        if rules { env.device.acceptCommunityRules(for: "sam") }
        return (env, fakes)
    }

    private func error(_ status: Int, _ code: String) -> APIError {
        APIError.client(status: status, detail: code, code: code, body: .object(["error_code": .string(code)]))
    }

    // MARK: Publish

    @Test func test_publishErrorRouting() async {
        let (env, fakes) = makeEnv()
        let model = PublishIdeaModel(env: env, planID: 7, kind: .plan, suggestedTitle: "Lisbon", track: { _ in })
        fakes.social.onPublish.fails(APIError.forbidden("Create a profile first."))
        await model.submit()
        guard case .failed(let missing) = model.phase else { Issue.record("expected failure"); return }
        #expect(missing.failure == .profileRequired)
        #expect(model.needsProfileEditor)
        model.openEditor()
        #expect(env.recordedRoutes == [.profileEditor])

        fakes.social.onPublish.fails(APIError.forbidden("Confirm your email first."))
        await model.submit()
        guard case .failed(let unverified) = model.phase else { Issue.record("expected failure"); return }
        #expect(unverified.failure == .emailUnverified)
        #expect(!model.needsProfileEditor)

        fakes.social.onPublish.fails(error(422, "limit_reached"))
        await model.submit()
        guard case .failed(let limit) = model.phase else { Issue.record("expected failure"); return }
        #expect(limit.failure == .limitReached)

        fakes.social.onPublish.fails(error(422, "content_rejected"))
        await model.submit()
        guard case .failed(let rejected) = model.phase else { Issue.record("expected failure"); return }
        #expect(rejected.failure == .contentRejected)
    }

    @Test func test_publishHeldAndPublishedAndTelemetry() async {
        let events = Events()
        let (env, fakes) = makeEnv()
        let model = PublishIdeaModel(env: env, planID: 7, kind: .recap, suggestedTitle: "Japan", track: { events.all.append($0) })
        fakes.social.onPublish.returns(FeedModelTests.idea("n", mine: true, status: .held))
        await model.submit()
        #expect(model.phase == .held)
        #expect(fakes.social.onPublish.lastCall?.planID == 7)
        #expect(fakes.social.onPublish.lastCall?.kind == .recap)
        let again = PublishIdeaModel(env: env, planID: 7, kind: .plan, suggestedTitle: "x", track: { events.all.append($0) })
        fakes.social.onPublish.returns(FeedModelTests.idea("n", mine: true))
        await again.submit()
        #expect(again.phase == .published)
        let kinds = events.all.compactMap { if case .socialIdeaPublish(let kind) = $0 { kind } else { nil } }
        #expect(kinds == ["recap", "plan"])
    }

    @Test func test_publishLimitsAndTrim() async {
        let (env, _) = makeEnv()
        let model = PublishIdeaModel(env: env, planID: 1, kind: .plan, track: { _ in })
        #expect(!model.canSubmit)
        model.title = "   "
        #expect(!model.canSubmit)
        model.title = String(repeating: "a", count: 200)
        model.caption = String(repeating: "b", count: 900)
        #expect(model.title.count == IdeaDraft.maxTitle)
        #expect(model.caption.count == IdeaDraft.maxCaption)
        #expect(model.canSubmit)
    }

    @Test func test_publishBlockedWhileProfileMissingOrPrivate() async {
        let (env, fakes) = makeEnv { $0.social.onProfile.returns(OwnProfile(handle: nil)) }
        let model = PublishIdeaModel(env: env, planID: 1, kind: .plan, suggestedTitle: "T", track: { _ in })
        await model.checkProfile()
        #expect(model.profile == .missing)
        #expect(!model.canSubmit)
        fakes.social.onProfile.returns(OwnProfile(handle: "ana", visibility: .private))
        await model.checkProfile()
        #expect(model.profile == .private)
        #expect(!model.canSubmit)
        fakes.social.onProfile.returns(OwnProfile(handle: "ana", visibility: .public))
        await model.checkProfile()
        #expect(model.canSubmit)
    }

    // MARK: Feed follows the detail and profile screens

    private func idea(_ id: String, author: String = "ana", mine: Bool = false) -> Idea {
        Idea(id: id, title: "Idea \(id)", caption: "c", author: IdeaAuthor(handle: author), mine: mine, status: .published)
    }

    @Test func test_blockingFromTheDetailScreenHidesTheAuthorInTheFeed() async {
        let (env, fakes) = makeEnv {
            $0.social.onFeed.returns(IdeaPage(ideas: [self.idea("1"), self.idea("2", author: "bo")], next: nil))
            $0.social.onIdea.returns(self.idea("1"))
        }
        let feed = FeedModel(env: env, track: { _ in })
        await feed.start()
        #expect(feed.visible.map(\.id) == ["1", "2"])
        let detail = IdeaDetailModel(env: env, ideaID: "1", track: { _ in })
        await detail.start()
        #expect(await detail.block())
        #expect(fakes.social.onBlock.lastCall == "ana")
        #expect(feed.visible.map(\.id) == ["2"])
    }

    @Test func test_blockingFromTheProfileHidesTheAuthorInTheFeed() async {
        let (env, _) = makeEnv {
            $0.social.onFeed.returns(IdeaPage(ideas: [self.idea("1"), self.idea("2", author: "bo")], next: nil))
        }
        let feed = FeedModel(env: env, track: { _ in })
        await feed.start()
        env.social.ledger.blocked(handle: "bo")
        #expect(feed.visible.map(\.id) == ["1"])
        env.social.ledger.unblocked(handle: "bo")
        #expect(feed.visible.map(\.id) == ["1", "2"])
    }

    @Test func test_deletingOwnIdeaFromTheDetailScreenRemovesItFromTheFeed() async {
        let (env, fakes) = makeEnv {
            $0.social.onFeed.returns(IdeaPage(ideas: [self.idea("1", mine: true), self.idea("2")], next: nil))
            $0.social.onIdea.returns(self.idea("1", mine: true))
        }
        let feed = FeedModel(env: env, track: { _ in })
        await feed.start()
        let detail = IdeaDetailModel(env: env, ideaID: "1", track: { _ in })
        await detail.start()
        await detail.delete()
        #expect(fakes.social.onDeleteIdea.lastCall == "1")
        #expect(feed.visible.map(\.id) == ["2"])
    }

    // MARK: Detail comments

    @Test func test_commentCountUpdatesForANonAuthorAndKnowsAuthorship() async {
        let (env, _) = makeEnv {
            $0.social.onIdea.returns(self.idea("1", mine: false))
            $0.social.onComments.returns(CommentPage(comments: []))
            $0.social.onComment.returns(IdeaComment(id: "c9", authorHandle: "sam", text: "Hi", mine: true))
        }
        let detail = IdeaDetailModel(env: env, ideaID: "1", track: { _ in })
        await detail.start()
        #expect(!detail.comments.ideaMine)
        let before = detail.idea?.comments ?? 0
        detail.comments.draft = "Hi"
        await detail.comments.post()
        #expect(detail.idea?.comments == before + 1)
    }

    @Test func test_detailTellsCommentsWhenTheViewerWroteTheIdea() async {
        let (env, _) = makeEnv { $0.social.onIdea.returns(self.idea("1", mine: true)) }
        let detail = IdeaDetailModel(env: env, ideaID: "1", track: { _ in })
        let comments = detail.comments
        await detail.start()
        // The same model instance (its draft survives), now in author mode.
        #expect(detail.comments === comments && comments.ideaMine)
    }

    // MARK: Comments

    @Test func test_helpfulOnlyForIdeaAuthor() async {
        let (env, fakes) = makeEnv()
        let other = IdeaComment(id: "c1", authorHandle: "bo", text: "Nice")
        let mine = IdeaComment(id: "c2", authorHandle: "me", text: "Thanks", mine: true)
        let asAuthor = CommentsModel(env: env, ideaID: "1", ideaMine: true, track: { _ in })
        #expect(asAuthor.canMarkHelpful(other))
        #expect(!asAuthor.canMarkHelpful(mine))
        #expect(asAuthor.canDelete(other))
        let asReader = CommentsModel(env: env, ideaID: "1", ideaMine: false, track: { _ in })
        #expect(!asReader.canMarkHelpful(other))
        #expect(!asReader.canDelete(other))
        #expect(asReader.canDelete(mine))
        await asReader.toggleHelpful(other)
        #expect(fakes.social.onMarkHelpful.callCount == 0)
    }

    @Test func test_commentsOldestFirstPostDeleteHelpful() async {
        let events = Events()
        let (env, fakes) = makeEnv {
            $0.social.onComments.returns(
                CommentPage(comments: [IdeaComment(id: "c1", authorHandle: "bo", text: "First")], next: "n2"))
        }
        var delta = 0
        let model = CommentsModel(env: env, ideaID: "1", ideaMine: true, onCount: { delta += $0 }, track: { events.all.append($0) })
        await model.start()
        #expect(model.visible.map(\.id) == ["c1"])
        fakes.social.onComments.returns(CommentPage(comments: [IdeaComment(id: "c2", authorHandle: "cy", text: "Second")]))
        await model.loadMore()
        #expect(model.visible.map(\.id) == ["c1", "c2"])
        fakes.social.onComment.returns(IdeaComment(id: "c3", authorHandle: "me", text: "Hi", mine: true))
        model.draft = "  Hi  "
        await model.post()
        #expect(fakes.social.onComment.lastCall?.text == "Hi")
        #expect(model.draft.isEmpty)
        #expect(delta == 1)
        await model.toggleHelpful(model.visible[0])
        #expect(fakes.social.onMarkHelpful.calls == ["c1"])
        #expect(model.visible[0].helpful)
        await model.delete(model.visible[2])
        #expect(delta == 0)
        #expect(events.all.count == 1)
    }

    // MARK: Community rules (R13)

    @Test func test_firstPublishWaitsForRulesThenSendsOnce() async {
        let (env, fakes) = makeEnv(rules: false)
        let model = PublishIdeaModel(env: env, planID: 7, kind: .plan, suggestedTitle: "Lisbon", track: { _ in })
        fakes.social.onPublish.returns(FeedModelTests.idea("n", mine: true))
        await model.submit()
        #expect(model.needsRules)
        #expect(fakes.social.onPublish.callCount == 0)
        model.declineRules()
        #expect(!model.needsRules && model.phase == .form)
        await model.submit()
        await model.acceptRules()
        #expect(!model.needsRules && model.phase == .published)
        #expect(fakes.social.onPublish.callCount == 1)
        #expect(env.device.hasAcceptedCommunityRules(for: "sam"))
        let again = PublishIdeaModel(env: env, planID: 7, kind: .plan, suggestedTitle: "Lisbon", track: { _ in })
        await again.submit()
        #expect(!again.needsRules && fakes.social.onPublish.callCount == 2)
    }

    @Test func test_firstCommentWaitsForRulesThenPosts() async {
        let (env, fakes) = makeEnv(rules: false) {
            $0.social.onComments.returns(CommentPage(comments: []))
        }
        fakes.social.onComment.returns(IdeaComment(id: "c3", authorHandle: "me", text: "Hi", mine: true))
        let model = CommentsModel(env: env, ideaID: "1", ideaMine: false, track: { _ in })
        await model.start()
        model.draft = "Hi"
        await model.post()
        #expect(model.needsRules && fakes.social.onComment.callCount == 0 && model.draft == "Hi")
        await model.acceptRules()
        #expect(!model.needsRules && model.draft.isEmpty && fakes.social.onComment.callCount == 1)
    }

    @Test func test_commentDraftCappedAt300() {
        let (env, _) = makeEnv()
        let model = CommentsModel(env: env, ideaID: "1", ideaMine: false, track: { _ in })
        model.draft = String(repeating: "x", count: 500)
        #expect(model.draft.count == 300)
    }

    // MARK: Report

    @Test func test_everyReportReasonMapped() async {
        let (env, fakes) = makeEnv()
        #expect(ReportReason.allCases.count == 6)
        for reason in ReportReason.allCases {
            let title = ReportSheetView.title(reason)
            #expect(!title.isEmpty && !title.contains("social:"))
            let model = ReportModel(target: .idea, id: "9", env: env)
            model.reason = reason
            await model.submit()
            #expect(model.phase == .sent)
            #expect(fakes.social.onReport.lastCall?.reason == reason)
        }
    }

    @Test func test_reportNoteClampedAndTracked() async {
        let events = Events()
        let (_, fakes) = makeEnv()
        let model = ReportModel(target: .comment, id: "c", send: { request in
            try await fakes.social.report(request)
            events.all.append(.socialReport(target: request.target.rawValue, reason: request.reason.rawValue))
        })
        model.note = String(repeating: "n", count: 400)
        #expect(model.note.count == 200)
        await model.submit()
        #expect(fakes.social.onReport.lastCall?.target == .comment)
    }

    // MARK: Detail

    @Test func test_detailGoneWhenHiddenOrNotFound() async {
        let (env, _) = makeEnv { $0.social.onIdea.returns(FeedModelTests.idea("1", status: .hidden)) }
        let hidden = IdeaDetailModel(env: env, ideaID: "1", track: { _ in })
        await hidden.load()
        #expect(hidden.phase == .gone)
        let (env2, _) = makeEnv { $0.social.onIdea.fails(APIError.notFound("Idea not found.")) }
        let missing = IdeaDetailModel(env: env2, ideaID: "1", track: { _ in })
        await missing.load()
        #expect(missing.phase == .gone)
        let (env3, _) = makeEnv { $0.social.onIdea.returns(FeedModelTests.idea("1", mine: true, status: .held)) }
        let held = IdeaDetailModel(env: env3, ideaID: "1", track: { _ in })
        await held.load()
        #expect(held.phase == .loaded)
    }

    // MARK: Support, failures

    @Test func test_supportRowHiddenWhenEmpty() {
        #expect(SupportRow(url: nil).url == nil)
        let build = AppBuildConfig(baseURL: nil, trustedHosts: [], appVersion: "1", isDebug: false)
        #expect(build.supportURL == nil)
    }

    @Test func test_failureMessagesAreTranslatedNotRawKeys() {
        let codes: [SocialFailureSample] = [
            .init(APIError.forbidden("Confirm your email first.")), .init(APIError.notFound("Idea not found.")),
            .init(APIError.forbidden("Create a profile first.")), .init(APIError.forbidden("Account restricted.")),
        ]
        for sample in codes { #expect(!sample.failure.message.contains(":")) }
        #expect(IdeaFailure(SocialService.Unavailable()).unavailable)
    }

    @Test func test_backendCodesWithEnglishTextAreTranslated() {
        func message(_ code: SocialFailure, detail: String) -> String {
            IdeaFailure(failure: code, kind: .other, detail: detail).message
        }
        #expect(message(.textInvalid, detail: "Text is invalid.") == L10n.text(K.social.errors.content_rejected))
        #expect(message(.handleRateLimited, detail: "Handle changed too recently.") == L10n.text(K.social.errors.handle_rate_limited))
        #expect(message(.snapshotTooLarge, detail: "Snapshot too large.") == L10n.text(K.errors.generic))
        #expect(message(.emailUnverified, detail: "Verify email.") == L10n.text(K.social.errors.email_unverified))
    }

    struct SocialFailureSample {
        let failure: IdeaFailure
        init(_ error: APIError) { failure = IdeaFailure(error) }
    }

    @Test func test_shareSheetOffersIdeasOnlyWithSocial() {
        let (on, _) = makeEnv()
        let (off, _) = makeEnv(social: false)
        #expect(on.social.isAvailable)
        #expect(!off.social.isAvailable)
    }
}
