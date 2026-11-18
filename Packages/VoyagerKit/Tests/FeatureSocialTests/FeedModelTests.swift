import Foundation
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureSocial

@MainActor
struct FeedModelTests {
    final class Events {
        var all: [TelemetryEvent] = []
        var likes: [Bool] { all.compactMap { if case .socialIdeaLike(let on) = $0 { on } else { nil } } }
        var scopes: [String] { all.compactMap { if case .socialFeedView(let scope) = $0 { scope } else { nil } } }
        var saves: Int { all.filter { if case .socialIdeaSave = $0 { true } else { false } }.count }
    }

    struct Rig {
        let model: FeedModel
        let fakes: FakeRepositories
        let env: AppEnvironment
        let events: Events
    }

    static func idea(
        _ id: String, mine: Bool = false, status: IdeaStatus = .published, liked: Bool = false, saved: Bool = false, likes: Int = 2
    ) -> Idea {
        Idea(
            id: id, title: "Idea \(id)", caption: "Caption", author: IdeaAuthor(handle: "ana_\(id)"), likes: likes, liked: liked,
            saved: saved, mine: mine, status: status)
    }

    func rig(social: Bool = true, configure: (FakeRepositories) -> Void = { _ in }) -> Rig {
        let fakes = FakeRepositories()
        configure(fakes)
        let features: [String: JSONValue] = social ? ["social": .number(1)] : [:]
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: features))
        let events = Events()
        return Rig(model: FeedModel(env: env, track: { events.all.append($0) }), fakes: fakes, env: env, events: events)
    }

    @Test func test_feedLoadsAndTracksScope() async {
        let r = rig { $0.social.onFeed.returns(IdeaPage(ideas: [Self.idea("1"), Self.idea("2")], next: "c1")) }
        await r.model.start()
        #expect(r.model.visible.map(\.id) == ["1", "2"])
        #expect(r.model.hasMore)
        #expect(r.events.scopes == ["for_you"])
        #expect(r.fakes.social.onFeed.lastCall?.scope == .forYou)
    }

    @Test func test_cursorPagingAppendsWithoutDuplicates() async {
        let r = rig { $0.social.onFeed.returns(IdeaPage(ideas: [Self.idea("1")], next: "c1")) }
        await r.model.start()
        r.fakes.social.onFeed.returns(IdeaPage(ideas: [Self.idea("1"), Self.idea("2")], next: nil))
        await r.model.loadMore()
        #expect(r.model.visible.map(\.id) == ["1", "2"])
        #expect(!r.model.hasMore)
        #expect(r.fakes.social.onFeed.lastCall?.cursor == "c1")
    }

    @Test func test_scopeSwitchReloads() async {
        let r = rig()
        await r.model.start()
        await r.model.select(.following)
        #expect(r.fakes.social.onFeed.lastCall?.scope == .following)
        #expect(r.events.scopes == ["for_you", "following"])
    }

    @Test func test_feedEmptyAndError() async {
        let empty = rig()
        await empty.model.start()
        #expect(empty.model.isEmpty)

        let failing = rig { $0.social.onFeed.fails(APIError.network) }
        await failing.model.start()
        guard case .failed(let failure) = failing.model.phase else {
            Issue.record("expected failed")
            return
        }
        #expect(failure.kind == .network)
        #expect(failing.model.visible.isEmpty)
    }

    @Test func test_flagOffNeverCallsRoutes() async {
        let r = rig(social: false)
        await r.model.start()
        #expect(r.model.phase == .unavailable)
        #expect(r.fakes.social.onFeed.callCount == 0)
        #expect(r.fakes.social.onProfile.callCount == 0)
    }

    @Test func test_heldNoticeOnlyToAuthor() async {
        let r = rig {
            $0.social.onFeed.returns(
                IdeaPage(ideas: [
                    Self.idea("pub"), Self.idea("mine-held", mine: true, status: .held), Self.idea("other-held", status: .held),
                    Self.idea("hid", status: .hidden), Self.idea("rem", status: .removed), Self.idea("odd", status: .unknown("x")),
                ]))
        }
        await r.model.start()
        #expect(r.model.visible.map(\.id) == ["pub", "mine-held"])
    }

    @Test func test_likeIdempotent() async {
        let r = rig { $0.social.onFeed.returns(IdeaPage(ideas: [Self.idea("1", likes: 2)])) }
        await r.model.start()
        await r.model.toggleLike("1")
        #expect(r.model.visible[0].liked)
        #expect(r.model.visible[0].likes == 3)
        #expect(r.fakes.social.onLike.calls == ["1"])
        await r.model.toggleLike("1")
        #expect(!r.model.visible[0].liked)
        #expect(r.model.visible[0].likes == 2)
        #expect(r.fakes.social.onUnlike.calls == ["1"])
        #expect(r.events.likes == [true, false])
    }

    @Test func test_likeFailurePutsCardBack() async {
        let r = rig { $0.social.onFeed.returns(IdeaPage(ideas: [Self.idea("1", likes: 0)])) }
        await r.model.start()
        r.fakes.social.onLike.fails(APIError.server(status: 500, detail: nil))
        await r.model.toggleLike("1")
        #expect(!r.model.visible[0].liked)
        #expect(r.model.visible[0].likes == 0)
        #expect(r.model.actionFailure["1"] != nil)
        #expect(r.events.likes.isEmpty)
    }

    @Test func test_saveOpensNewPlan() async {
        let r = rig { $0.social.onFeed.returns(IdeaPage(ideas: [Self.idea("1")])) }
        await r.model.start()
        r.fakes.social.onSave.returns(42)
        await r.model.save("1")
        #expect(r.env.recordedRoutes.contains(.planDetail(id: 42)))
        #expect(r.model.visible[0].saved)
        #expect(r.model.savedNote.contains("1"))
        #expect(r.events.saves == 1)
    }

    @Test func test_deleteOnlyOwnIdea() async {
        let r = rig { $0.social.onFeed.returns(IdeaPage(ideas: [Self.idea("a"), Self.idea("b", mine: true)])) }
        await r.model.start()
        await r.model.delete("a")
        #expect(r.fakes.social.onDeleteIdea.callCount == 0)
        await r.model.delete("b")
        #expect(r.fakes.social.onDeleteIdea.calls == ["b"])
        #expect(r.model.visible.map(\.id) == ["a"])
    }

    @Test func test_blockedAuthorLeavesTheList() async {
        let r = rig { $0.social.onFeed.returns(IdeaPage(ideas: [Self.idea("a"), Self.idea("b")])) }
        await r.model.start()
        r.model.blocked(handle: "ana_a")
        #expect(r.model.visible.map(\.id) == ["b"])
    }

    @Test func test_feedBlockGoesThroughTheLedger() async {
        let r = rig { $0.social.onFeed.returns(IdeaPage(ideas: [Self.idea("a"), Self.idea("b")])) }
        await r.model.start()
        await r.model.block(handle: "ana_a")
        #expect(r.env.social.ledger.hides(ideaID: "zzz", authorHandle: "ana_a"))
        #expect(r.model.visible.map(\.id) == ["b"])
    }

    @Test func test_profilePromptWhenNoHandle() async {
        let r = rig()
        await r.model.start()
        #expect(r.model.showsProfilePrompt)
        let withHandle = rig { $0.social.onProfile.returns(OwnProfile(handle: "ana")) }
        await withHandle.model.start()
        #expect(!withHandle.model.showsProfilePrompt)
    }

    @Test func test_openingAnIdeaRoutesAndTracks() async {
        let r = rig()
        await r.model.start()
        r.model.opened(Self.idea("9"))
        #expect(r.env.recordedRoutes == [.ideaDetail(id: "9")])
    }

    @Test func test_snapshotFactsReadDefensively() {
        let snapshot: JSONValue = .object([
            "destinations": .array([.string("Lisbon"), .number(3)]), "days": .number(5),
            "stats": .array([
                .object(["key": .string("hotels"), "count": .number(2)]), .object(["key": .string("zzz"), "count": .number(1)]),
            ]),
            "items": .object(["activities": .array([.object(["name": .string("Tram 28")]), .object([:])])]),
        ])
        let facts = IdeaFacts(snapshot: snapshot)
        #expect(facts.destinations == ["Lisbon"])
        #expect(facts.days == 5)
        #expect(facts.stats == [IdeaFacts.Stat(key: .hotels, count: 2)])
        #expect(facts.itemNames == ["Tram 28"])
        #expect(IdeaFacts(snapshot: .null).isEmpty)
    }
}
