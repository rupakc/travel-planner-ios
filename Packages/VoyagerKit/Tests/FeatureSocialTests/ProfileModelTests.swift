import AuthCore
import Foundation
import L10n
import Networking
@testable import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureSocial

@MainActor
struct ProfileModelTests {
    final class Events { var all: [TelemetryEvent] = [] }

    private func env(
        user: String = "sam", fakes: FakeRepositories = FakeRepositories(), social: Bool = true, game: Bool = false
    ) -> AppEnvironment {
        var features: [String: JSONValue] = ["social": .number(social ? 1 : 0)]
        if game { features["game"] = .number(1) }
        return AppEnvironment.fake(user: User(username: user), fakes: fakes, clientConfig: ClientConfig(features: features))
    }

    private func error(_ status: Int, _ code: String, extra: [String: JSONValue] = [:]) -> APIError {
        var body: [String: JSONValue] = ["error_code": .string(code)]
        body.merge(extra) { $1 }
        return .client(status: status, detail: "x", code: code, body: .object(body))
    }

    private func editor(
        _ environment: AppEnvironment, events: Events = Events(), visibility: any GameVisibility = StaticGameVisibility.hidden
    ) -> ProfileEditorModel {
        ProfileEditorModel(
            env: environment, sleep: { _ in await Task.yield() }, gameVisibility: { visibility }, track: { events.all.append($0) })
    }

    // MARK: Editor

    @Test func test_gameSwitchesFollowPlaysGameHiddenAnswer() async {
        let fakes = FakeRepositories()
        fakes.play.onState.fails(APIError.forbidden("Play and points are hidden in your account."))
        let environment = AppEnvironment.fake(
            user: User(username: "sam"), fakes: fakes,
            clientConfig: ClientConfig(features: ["social": .number(1), "play": .number(1), "game": .number(1)]))
        #expect(ProfileEditorModel.defaultGameVisibility(env: environment).showsGame, "visible until the server says otherwise")
        _ = try? await environment.play.call { try await $0.state() }
        #expect(environment.play.isHiddenByServer)
        #expect(!ProfileEditorModel.defaultGameVisibility(env: environment).showsGame)
    }

    @Test func test_everyToggleDefaultsOff() async {
        let model = editor(env())
        await model.load()
        #expect(model.isNew)
        #expect(model.visibility == .private)
        #expect(!model.showAvatar && !model.showHomeCountry && !model.showCountries)
        #expect(!model.showLevel && !model.showBadges && !model.leaderboardOptIn)
        #expect(model.homeCountry == nil)
    }

    @Test func test_handleCheckDebounced() async {
        let fakes = FakeRepositories()
        let model = editor(env(fakes: fakes))
        await model.load()
        for text in ["a", "ab", "abc", "abcd", "abcde"] { model.setHandle(text) }
        await model.pendingCheck?.value
        #expect(fakes.social.onCheckHandle.calls == ["abcde"])
        #expect(model.handleStatus == .available)
    }

    @Test func test_invalidHandleNeverReachesTheServer() async {
        let fakes = FakeRepositories()
        let model = editor(env(fakes: fakes))
        await model.load()
        model.setHandle("a!")
        await model.pendingCheck?.value
        #expect(fakes.social.onCheckHandle.callCount == 0)
        #expect(model.handleStatus == .unavailable(L10n.text(K.social.editor.handleReason.invalid)))
    }

    @Test func test_takenHandleBlocksSave() async {
        let fakes = FakeRepositories()
        fakes.social.onCheckHandle.returns(HandleCheck(available: false, reason: .taken))
        let model = editor(env(fakes: fakes))
        await model.load()
        model.setHandle("sam_t")
        await model.pendingCheck?.value
        #expect(model.handleStatus == .unavailable(L10n.text(K.social.editor.handleReason.taken)))
        #expect(!model.canSave)
    }

    @Test func test_handleChangeRateLimitedMessage() async {
        let fakes = FakeRepositories()
        fakes.social.onProfile.returns(OwnProfile(handle: "sam_t"))
        fakes.social.onSaveProfile.fails(error(422, "handle_rate_limited", extra: ["retry_after": .number(86400)]))
        let environment = env(fakes: fakes)
        environment.device.acceptCommunityRules(for: "sam")
        let model = editor(environment)
        await model.load()
        model.setHandle("sam_two")
        await model.pendingCheck?.value
        await model.save()
        #expect(model.noticeText == L10n.text(K.social.errors.handle_rate_limited))
    }

    @Test func test_rulesAcceptedOncePerUser() async {
        let fakes = FakeRepositories()
        fakes.social.onSaveProfile.returns(OwnProfile(handle: "sam_t", visibility: .public))
        let environment = env(fakes: fakes)
        let model = editor(environment)
        await model.load()
        model.setHandle("sam_t")
        await model.pendingCheck?.value
        await model.save()
        #expect(model.needsRules)
        #expect(fakes.social.onSaveProfile.callCount == 0)
        await model.acceptRules()
        #expect(!model.needsRules)
        #expect(fakes.social.onSaveProfile.callCount == 1)
        // The same user saving again is not asked; another user on the device is.
        model.visibility = .followers
        await model.save()
        #expect(!model.needsRules)
        #expect(fakes.social.onSaveProfile.callCount == 2)
        let other = editor(self.env(user: "kim", fakes: fakes))
        await other.load()
        #expect(!other.rulesAccepted)
    }

    @Test func test_newProfileSendsEverythingAndExistingOnlyChanges() async {
        let fakes = FakeRepositories()
        let model = editor(env(fakes: fakes))
        await model.load()
        model.setHandle("sam_t")
        let full = model.patch(forNew: true)
        #expect(full.handle == "sam_t" && full.visibility == .private && full.showAvatar == false && full.bio == "")
        fakes.social.onProfile.returns(OwnProfile(handle: "sam_t", bio: "hi"))
        let existing = editor(env(fakes: fakes))
        await existing.load()
        #expect(existing.patch(forNew: false).isEmpty)
        existing.showAvatar = true
        let delta = existing.patch(forNew: false)
        #expect(delta.showAvatar == true && delta.handle == nil && delta.bio == nil)
    }

    @Test func test_bioCappedAt160() async {
        let model = editor(env())
        await model.load()
        model.setBio(String(repeating: "x", count: 300))
        #expect(model.bioCount == 160)
    }

    @Test func test_saveEmitsVisibilityOnly() async {
        let fakes = FakeRepositories()
        fakes.social.onSaveProfile.returns(OwnProfile(handle: "sam_t", visibility: .followers))
        let environment = env(fakes: fakes)
        environment.device.acceptCommunityRules(for: "sam")
        let events = Events()
        let model = editor(environment, events: events)
        await model.load()
        model.setHandle("sam_t")
        await model.pendingCheck?.value
        await model.save()
        let names = events.all.map(\.wire.name)
        #expect(names == ["social_profile_view", "social_profile_save"])
        #expect(events.all.last?.wire.props["visibility"] == .string("followers"))
    }

    @Test func test_gameFieldsHiddenWhenHideGame() async {
        let hidden = editor(env(), visibility: StaticGameVisibility.hidden)
        let shown = editor(env(), visibility: StaticGameVisibility.visible)
        #expect(!hidden.showsGameFields)
        #expect(shown.showsGameFields)
    }

    @Test func test_flagOffIsUnavailableWithoutACall() async {
        let fakes = FakeRepositories()
        let model = editor(env(fakes: fakes, social: false))
        await model.load()
        #expect(model.phase == .unavailable)
        #expect(fakes.social.onProfile.callCount == 0)
    }

    // MARK: Public profile

    private func profile(following: Bool = false, pending: Bool = false, level: Int? = nil) -> PublicProfile {
        PublicProfile(
            handle: "ana", bio: "**bold**", homeCountry: "PT", countries: ["JP"], level: level,
            badges: level == nil ? nil : [ProfileBadge(id: "first_trip")], ideasCount: 2, followersCount: 5, followingCount: 1,
            you: ProfileRelation(following: following, pending: pending, followsYou: true))
    }

    private func publicModel(
        _ fakes: FakeRepositories, visibility: any GameVisibility = StaticGameVisibility.visible, events: Events = Events()
    ) -> PublicProfileModel {
        PublicProfileModel(env: env(fakes: fakes), handle: "@Ana", gameVisibility: { visibility }, track: { events.all.append($0) })
    }

    @Test func test_pendingStateForFollowersProfile() async {
        let fakes = FakeRepositories()
        fakes.social.onPublicProfile.returns(profile())
        fakes.social.onFollow.returns(.pending)
        let events = Events()
        let model = publicModel(fakes, events: events)
        await model.load()
        #expect(model.relation == .none)
        await model.toggleFollow()
        #expect(model.relation == .pending)
        #expect(model.profile?.followersCount == 5)
        #expect(events.all.last?.wire.props["state"] == .string("pending"))
        await model.toggleFollow()
        #expect(model.relation == .none)
        #expect(fakes.social.onUnfollow.calls == ["ana"])
    }

    @Test func test_followWithoutProfileAsksForOne() async {
        let fakes = FakeRepositories()
        fakes.social.onPublicProfile.returns(profile())
        fakes.social.onFollow.fails(APIError.forbidden("Create a profile first."))
        let model = publicModel(fakes)
        await model.load()
        await model.toggleFollow()
        #expect(model.notice == .profileRequired)
        #expect(model.relation == .none)
    }

    @Test func test_blockIsSilentAndTwoWay() async {
        let fakes = FakeRepositories()
        fakes.social.onPublicProfile.returns(profile(following: true))
        let events = Events()
        let model = publicModel(fakes, events: events)
        await model.load()
        model.askBlock()
        await model.confirmBlock()
        #expect(fakes.social.onBlock.calls == ["ana"])
        #expect(model.blocked && model.profile == nil && model.phase == .notFound)
        #expect(events.all.last?.wire.name == "social_block")
        // A blocked pair is a plain 404 for the other side as well.
        let other = FakeRepositories()
        other.social.onPublicProfile.fails(APIError.notFound("Profile not found."))
        let gone = publicModel(other)
        await gone.load()
        #expect(gone.phase == .notFound)
    }

    @Test func test_levelBadgesHiddenWhenHideGame() async {
        let fakes = FakeRepositories()
        fakes.social.onPublicProfile.returns(profile(level: 4))
        let hidden = publicModel(fakes, visibility: StaticGameVisibility.hidden)
        await hidden.load()
        #expect(!hidden.showsLevel && !hidden.showsBadges)
        let unreadable = publicModel(fakes, visibility: StaticGameVisibility.unreadable)
        await unreadable.load()
        #expect(!unreadable.showsLevel)
        let shown = publicModel(fakes)
        await shown.load()
        #expect(shown.showsLevel && shown.showsBadges)
    }

    @Test func test_optionalFieldsOnlyWhenSent() async {
        let fakes = FakeRepositories()
        fakes.social.onPublicProfile.returns(PublicProfile(handle: "ana"))
        let model = publicModel(fakes)
        await model.load()
        #expect(model.countryName == nil && model.visitedNames.isEmpty && !model.showsLevel)
    }

    @Test func test_ownProfileShowsEdit() async {
        let fakes = FakeRepositories()
        fakes.social.onPublicProfile.returns(profile())
        fakes.social.onProfile.returns(OwnProfile(handle: "Ana"))
        let model = publicModel(fakes)
        await model.load()
        #expect(model.isMine)
        await model.toggleFollow()
        #expect(fakes.social.onFollow.callCount == 0)
    }

    // MARK: Report and lists

    @Test func test_reportSendsProfileTargetAndEmitsReason() async {
        let fakes = FakeRepositories()
        let events = Events()
        let model = ProfileReportModel(env: env(fakes: fakes), handle: "ana", track: { events.all.append($0) })
        model.reason = .abuse
        model.setNote(String(repeating: "n", count: 400))
        await model.send()
        #expect(model.phase == .sent)
        #expect(fakes.social.onReport.lastCall?.target == .profile && fakes.social.onReport.lastCall?.reason == .abuse)
        #expect(model.note.count == 200)
        #expect(events.all.last?.wire.props["reason"] == .string("abuse"))
    }

    @Test func test_requestsAcceptDeclineAndGone() async {
        let fakes = FakeRepositories()
        fakes.social.onFollowRequests.returns([FollowRequest(handle: "a1"), FollowRequest(handle: "b2"), FollowRequest(handle: "c3")])
        fakes.social.onDeclineRequest.fails(APIError.notFound("Follow request not found."))
        let model = ProfileListModel(env: env(fakes: fakes), kind: .requests, track: { _ in })
        await model.load()
        await model.accept(ProfilePerson(handle: "a1"))
        await model.decline(ProfilePerson(handle: "b2"))
        #expect(model.people.map(\.handle) == ["c3"])
        #expect(fakes.social.onAcceptRequest.calls == ["a1"])
    }

    @Test func test_blockListUnblocks() async {
        let fakes = FakeRepositories()
        fakes.social.onBlocks.returns([HandleUser(handle: "zed")])
        let events = Events()
        let model = ProfileListModel(env: env(fakes: fakes), kind: .blocked, track: { events.all.append($0) })
        await model.load()
        await model.unblock(ProfilePerson(handle: "zed"))
        #expect(model.people.isEmpty)
        #expect(events.all.last?.wire.props["on"] == .bool(false))
    }

    @Test func test_followersPageThroughCursor() async {
        let fakes = FakeRepositories()
        fakes.social.onFollowers.handler = { cursor in
            cursor == nil
                ? UserPage(users: [HandleUser(handle: "a1")], next: "c1") : UserPage(users: [HandleUser(handle: "b2")], next: nil)
        }
        let model = ProfileListModel(env: env(fakes: fakes), kind: .followers, track: { _ in })
        await model.load()
        #expect(model.canLoadMore)
        await model.loadMore()
        #expect(model.people.map(\.handle) == ["a1", "b2"] && !model.canLoadMore)
    }
}
