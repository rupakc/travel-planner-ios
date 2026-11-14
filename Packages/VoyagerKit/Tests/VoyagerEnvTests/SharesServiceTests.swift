import AuthCore
import Foundation
import Networking
import Testing
import TestSupport
import VoyagerModel

@testable import VoyagerEnv

@MainActor
@Suite struct SharesServiceTests {
    private func config(sharing: Int = 1) -> ClientConfig {
        ClientConfig(features: ["sharing": .number(Double(sharing))])
    }

    private let share = Share(token: "t1", kind: .plan, planID: 3, url: "https://h/share/t1")

    private func tempStore() -> ShareCardStore {
        ShareCardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("cards-\(UUID().uuidString)"))
    }

    // MARK: Flag

    @Test func test_olderBackendNeverCallsAnyRoute() async {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes)  // no /config: every flag is off
        #expect(!env.shares.isAvailable)
        await #expect(throws: SharesService.Unavailable.self) { try await env.shares.create(ShareRequest(kind: .plan, planID: 3)) }
        await #expect(throws: SharesService.Unavailable.self) { try await env.shares.list() }
        await #expect(throws: SharesService.Unavailable.self) { try await env.shares.revoke(token: "t1") }
        #expect(fakes.shares.onCreate.callCount == 0 && fakes.shares.onList.callCount == 0 && fakes.shares.onRevoke.callCount == 0)
        let zero = AppEnvironment.fake(fakes: fakes, clientConfig: config(sharing: 0))
        #expect(!zero.shares.isAvailable)
    }

    @Test func test_flagOnCallsTheRoutes() async throws {
        let fakes = FakeRepositories()
        fakes.shares.onCreate.returns(share)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        #expect(env.shares.isAvailable)
        let made = try await env.shares.create(ShareRequest(kind: .plan, planID: 3))
        #expect(made.token == "t1" && fakes.shares.onCreate.lastCall?.planID == 3)
        try await env.shares.revoke(token: "t1")
        #expect(fakes.shares.onRevoke.lastCall == "t1")
    }

    @Test func test_sharingDisabledOrMissingRouteTurnsTheFeatureOffForTheSession() async {
        for error in [APIError.notFound("Sharing is not available."), APIError.notFound("Not Found")] {
            let fakes = FakeRepositories()
            fakes.shares.onList.fails(error)
            let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
            await #expect(throws: APIError.self) { try await env.shares.list() }
            #expect(!env.shares.isAvailable)
            await #expect(throws: SharesService.Unavailable.self) { try await env.shares.list() }
            #expect(fakes.shares.onList.callCount == 1)
        }
    }

    @Test func test_otherFailuresKeepTheFeatureOn() async {
        let fakes = FakeRepositories()
        fakes.shares.onCreate.fails(APIError.notFound("Plan not found."))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        await #expect(throws: APIError.self) { try await env.shares.create(ShareRequest(kind: .plan, planID: 99)) }
        #expect(env.shares.isAvailable)
    }

    // MARK: Errors

    @Test func test_errorCodeMapping() {
        func client(_ status: Int, _ code: String) -> APIError {
            .client(status: status, detail: "x", code: nil, body: .object(["detail": .string("x"), "error_code": .string(code)]))
        }
        #expect(ShareFailure.from(client(422, "invalid_kind"), call: .create) == .invalidKind)
        #expect(ShareFailure.from(client(422, "no_active_trip"), call: .create) == .noActiveTrip)
        #expect(ShareFailure.from(.client(status: 422, detail: nil, code: "invalid_kind", body: .null), call: .create) == .invalidKind)
        #expect(ShareFailure.from(.notFound("Sharing is not available."), call: .create) == .sharingDisabled)
        #expect(ShareFailure.from(.notFound("Plan not found."), call: .create) == .planNotFound)
        #expect(ShareFailure.from(.notFound("Quiz session not found."), call: .create) == .sessionNotFound)
        #expect(ShareFailure.from(.notFound("Play is not available."), call: .create) == .playDisabled)
        #expect(ShareFailure.from(.notFound("Share not found."), call: .revoke) == .shareNotFound)
        #expect(ShareFailure.from(.notFound("Whatever"), call: .revoke) == .shareNotFound)
        #expect(ShareFailure.from(.notFound("Whatever"), call: .create) == nil)
        #expect(ShareFailure.from(.notFound("Not Found"), call: .revoke) == nil)
        #expect(ShareFailure.from(.notFound(nil), call: .list) == nil)
        #expect(ShareFailure.from(.server(status: 503, detail: nil, code: "card_busy"), call: .create) == .cardBusy)
        #expect(ShareFailure.from(.server(status: 503, detail: nil), call: .create) == nil)
        #expect(ShareFailure.from(.rateLimited(message: "slow down", retryAfter: 5), call: .create) == nil)
        #expect(ShareFailure.from(.network, call: .create) == nil)
        #expect(ShareFailure.from(client(422, "brand_new"), call: .create) == nil)
        #expect(ShareFailure.isRouteMissing(.notFound("Not Found")) && ShareFailure.isRouteMissing(.notFound(nil)))
        #expect(!ShareFailure.isRouteMissing(.notFound("Plan not found.")))
    }

    // MARK: Cards

    private func png() -> Data { FakeShareCardLoader.pixel }

    @Test func test_cardHostMustBeTrusted() async throws {
        let stub = StubServer { _ in .init(status: 200, headers: ["Content-Type": "image/png"], body: FakeShareCardLoader.pixel) }
        let store = tempStore()
        let url = try #require(URL(string: "https://\(stub.host)/api/share/t1/card.png?size=link"))
        let untrusted = LiveShareCardLoader(store: store, session: stub.session(), isTrusted: { _ in false })
        await #expect(throws: ShareCardError.untrustedHost) { try await untrusted.load(url, token: "t1", size: .link) }
        #expect(stub.requests.isEmpty)  // nothing was fetched
        let trusted = LiveShareCardLoader(store: store, session: stub.session(), isTrusted: { $0.host == stub.host })
        let file = try await trusted.load(url, token: "t1", size: .link)
        #expect(file.deletingLastPathComponent().path == store.directory.path)
        #expect(try Data(contentsOf: file) == png())
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)  // a public card never carries the session
        store.purge()
    }

    @Test func test_downloadFailuresAreTyped() async throws {
        let store = tempStore()
        func load(_ reply: StubServer.Reply) async throws -> URL {
            let stub = StubServer { _ in reply }
            let url = try #require(URL(string: "https://\(stub.host)/c.png"))
            return try await LiveShareCardLoader(store: store, session: stub.session(), isTrusted: { _ in true })
                .load(url, token: "t2", size: .story)
        }
        await #expect(throws: ShareCardError.badResponse) { try await load(.init(status: 503, json: #"{"error_code": "card_busy"}"#)) }
        await #expect(throws: ShareCardError.notAnImage) { try await load(.init(status: 200, body: Data("<html>".utf8))) }
        store.purge()
    }

    @Test func test_cardFileNamesStayInsideTheStore() {
        let store = tempStore()
        for token in ["../../etc/passwd", "a/b", "", String(repeating: "x", count: 200), "ok-Token_1"] {
            let file = store.fileURL(token: token, size: .link)
            #expect(file.deletingLastPathComponent().path == store.directory.path)
        }
        #expect(store.fileURL(token: "ok-Token_1", size: .story).lastPathComponent == "ok-Token_1-story.png")
    }

    @Test func test_tempCardsPurgedOnSignOut() async throws {
        let env = AppEnvironment.fake()
        env.shareCardStore = tempStore()
        let cards = env.shares.cards
        let file = try cards.write(png(), token: "purge-\(UUID().uuidString.prefix(8))", size: .link)
        #expect(FileManager.default.fileExists(atPath: file.path))
        _ = env.observeAuth()  // the signed-in user: first sight of a user purges the previous user's cards
        #expect(!FileManager.default.fileExists(atPath: file.path))

        let second = try cards.write(png(), token: "purge-\(UUID().uuidString.prefix(8))", size: .story)
        await env.auth.signOut()
        _ = env.observeAuth()
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test func test_purgeIsSafeWithoutADirectory() {
        let store = tempStore()
        store.purge()
        store.purge()
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
    }
}
