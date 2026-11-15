import Foundation
import Networking
import Testing
import TestSupport
import VoyagerData
import VoyagerEnv
import VoyagerModel

@MainActor
@Suite struct Phase5ServicesTests {
    private func config(social: Int = 1, play: Int = 1, game: Bool = true) -> ClientConfig {
        ClientConfig(features: ["social": .number(Double(social)), "play": .number(Double(play)), "game": .bool(game)])
    }

    // MARK: Flags

    @Test func test_flagsHideEntryPoints() async {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes)  // no /config: every flag is off
        #expect(!env.social.isAvailable && !env.play.isAvailable)
        await #expect(throws: SocialService.Unavailable.self) { try await env.social.call { try await $0.profile() } }
        await #expect(throws: PlayService.Unavailable.self) { try await env.play.call { try await $0.state() } }
        #expect(fakes.social.onProfile.callCount == 0 && fakes.play.onState.callCount == 0)
        let zero = AppEnvironment.fake(fakes: fakes, clientConfig: config(social: 0, play: 0))
        #expect(!zero.social.isAvailable && !zero.play.isAvailable)
    }

    @Test func test_socialAndPlayAreIndependent() {
        let socialOnly = AppEnvironment.fake(clientConfig: config(social: 1, play: 0))
        #expect(socialOnly.social.isAvailable && !socialOnly.play.isAvailable)
        let playOnly = AppEnvironment.fake(clientConfig: config(social: 0, play: 1))
        #expect(!playOnly.social.isAvailable && playOnly.play.isAvailable)
    }

    @Test func test_flagOnCallsTheRoutes() async throws {
        let fakes = FakeRepositories()
        fakes.social.onProfile.returns(OwnProfile(handle: "maria_k"))
        fakes.play.onState.returns(PlayState(openH2H: 2))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        #expect(try await env.social.call { try await $0.profile() }.handle == "maria_k")
        #expect(try await env.play.call { try await $0.state() }.openH2H == 2)
    }

    // MARK: Game hidden

    @Test func test_gameHiddenHidesPlay() async {
        let fakes = FakeRepositories()
        let explicit = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        explicit.play.hideGameSetting = { true }
        #expect(!explicit.play.isAvailable)
        await #expect(throws: PlayService.Unavailable.self) { try await explicit.play.call { try await $0.state() } }
        #expect(fakes.play.onState.callCount == 0)
        // The game flag off in `/config` means `play` is 0 on the server too.
        let gameOff = AppEnvironment.fake(clientConfig: config(play: 0, game: false))
        #expect(!gameOff.play.isAvailable)
        // Social is not game: it stays.
        explicit.play.hideGameSetting = { true }
        #expect(explicit.social.isAvailable)
    }

    @Test func test_unreadableSettingDoesNotBlockTheRoutesTheServerDecides() {
        let env = AppEnvironment.fake(clientConfig: config())
        #expect(env.play.hideGameSetting() == nil && env.play.isAvailable)
        env.play.hideGameSetting = { false }
        #expect(env.play.isAvailable)
    }

    @Test func test_gameHidden403HidesPlayUntilTheUserChanges() async {
        let fakes = FakeRepositories()
        fakes.play.onState.fails(APIError.forbidden("Play and points are hidden in your account."))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        await #expect(throws: APIError.self) { try await env.play.call { try await $0.state() } }
        #expect(env.play.isHiddenByServer && !env.play.isAvailable)
        await #expect(throws: PlayService.Unavailable.self) { try await env.play.call { try await $0.state() } }
        #expect(fakes.play.onState.callCount == 1)
        env.play.reset()
        #expect(env.play.isAvailable && !env.play.isHiddenByServer)
    }

    // MARK: 404 turns a feature off

    @Test func test_playRoutes404TurnsOff() async {
        for error in [APIError.notFound("Not found"), APIError.notFound("Not Found")] {
            let fakes = FakeRepositories()
            fakes.play.onState.fails(error)
            let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
            await #expect(throws: APIError.self) { try await env.play.call { try await $0.state() } }
            #expect(!env.play.isAvailable)
            await #expect(throws: PlayService.Unavailable.self) { try await env.play.call { try await $0.state() } }
            #expect(fakes.play.onState.callCount == 1)
        }
    }

    @Test func test_socialRoutes404TurnsOffButACodedNotFoundDoesNot() async {
        let fakes = FakeRepositories()
        fakes.social.onPublicProfile.fails(APIError.notFound("Profile not found."))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        await #expect(throws: APIError.self) { try await env.social.call { try await $0.publicProfile(handle: "a") } }
        #expect(env.social.isAvailable)
        fakes.social.onProfile.fails(APIError.notFound("Not found"))
        await #expect(throws: APIError.self) { try await env.social.call { try await $0.profile() } }
        #expect(!env.social.isAvailable)
        env.social.reset()
        #expect(env.social.isAvailable)
    }

    @Test func test_otherFailuresKeepTheFeaturesOn() async {
        let fakes = FakeRepositories()
        fakes.social.onFeed.fails(APIError.rateLimited(message: "slow down", retryAfter: 4))
        fakes.play.onState.fails(APIError.network)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        await #expect(throws: APIError.self) { try await env.social.call { try await $0.feed(scope: .new, cursor: nil, limit: nil) } }
        await #expect(throws: APIError.self) { try await env.play.call { try await $0.state() } }
        #expect(env.social.isAvailable && env.play.isAvailable)
    }

    @Test func test_theFakesRecordPagingCursors() async throws {
        let fakes = FakeRepositories()
        fakes.social.onFeed.returns(IdeaPage(ideas: [], next: "40"))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        let first = try await env.social.call { try await $0.feed(scope: .following, cursor: nil, limit: 30) }
        _ = try await env.social.call { try await $0.feed(scope: .following, cursor: first.next, limit: 30) }
        #expect(fakes.social.onFeed.calls.map { $0.cursor } == [nil, "40"])
        #expect(fakes.social.onFeed.calls.allSatisfy { $0.scope == .following })
    }
}
