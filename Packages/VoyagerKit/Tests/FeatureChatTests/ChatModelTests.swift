import Foundation
import Networking
import Telemetry
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureChat

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
    var searchSubmits: Int { events.filter { if case .searchSubmit(.chat, _, _, _) = $0 { true } else { false } }.count }
}

@MainActor
final class ChatModelTests: XCTestCase {
    private func make(
        replay events: [ChatStreamEvent]? = nil, thenFails error: (any Error & Sendable)? = nil
    ) -> (ChatModel, AppEnvironment, FakeChatRepository, Recorder) {
        let fakes = FakeRepositories()
        if let events { fakes.chat.onStream.replays(events, thenFails: error) }
        let env = AppEnvironment.fake(fakes: fakes)
        let recorder = Recorder()
        let model = ChatModel(env: env, track: { recorder.events.append($0) })
        return (model, env, fakes.chat, recorder)
    }

    private func events(_ name: String) -> [ChatStreamEvent] { Fixtures.sse(name).map(ChatStreamEvent.init(json:)) }

    private func settle(_ model: ChatModel, timeout: Double = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while model.isStreaming, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isStreaming)
    }

    func test_qaTurn() async {
        let (model, env, chat, recorder) = make(replay: events("chat_qa"))
        model.send("Do I need a visa for Thailand?")
        await settle(model)
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages.last?.content, "US citizens can visit **Thailand** visa-free for up to 60 days.")
        XCTAssertEqual(model.sessionContext["destination"].string, "Thailand")
        XCTAssertEqual(recorder.searchSubmits, 0)
        XCTAssertEqual(chat.onStream.lastCall?.messages.map(\.content), ["Do I need a visa for Thailand?"])
        XCTAssertEqual(env.chatThreads.threads.first?.messages.count, 2)
        XCTAssertEqual(env.chatThreads.threads.first?.title, "Do I need a visa for Thailand?")
    }

    func test_sessionContextIsSentBack() async {
        let (model, _, chat, _) = make(replay: events("chat_qa"))
        model.send("one")
        await settle(model)
        model.send("two")
        await settle(model)
        let last = chat.onStream.lastCall
        XCTAssertEqual(last?.sessionContext["destination"].string, "Thailand")
        XCTAssertEqual(last?.messages.map(\.role), ["user", "assistant", "user"])
    }

    func test_planningTelemetryOnlyWhenPlanningStarts() async {
        let (model, _, _, recorder) = make(replay: events("chat_planning"))
        model.send("plan Tokyo")
        await settle(model)
        XCTAssertEqual(recorder.searchSubmits, 1)
        XCTAssertNotNil(model.messages.last?.planning?.itinerary)
    }

    func test_planActionUpdatesStore() async {
        let (model, env, _, _) = make(replay: [
            .planAction(action: "add", field: "activities", data: ["name": "Tsukiji food tour"]), .delta("Added."), .done,
        ])
        model.send("add the food tour")
        await settle(model)
        XCTAssertEqual(env.plan.selections["activities"].array?.count, 1)
        XCTAssertEqual(env.plan.selections["activities"][0]["name"].string, "Tsukiji food tour")
    }

    func test_sectionResultFeedsLatestResults() async {
        let (model, env, _, _) = make(replay: events("chat_fallback"))
        model.send("hotels in Tokyo")
        await settle(model)
        XCTAssertNotNil(env.plan.latestResults["hotels"].object)
        XCTAssertEqual(env.recordedRoutes.count, 1)
    }

    func test_planningDoneEndsTurn() async {
        let (model, _, _, _) = make(replay: [.planningStart(destination: "Rome"), .itineraryGenerating, .planningDone])
        model.send("plan Rome")
        await settle(model)
        XCTAssertEqual(model.messages.last?.planning?.generating, false)
        XCTAssertEqual(model.messages.last?.planning?.done, true)
    }

    func test_deltaCoalesced() async {
        let deltas = (0..<300).map { ChatStreamEvent.delta("w\($0) ") }
        let (model, _, _, _) = make(replay: deltas + [.done])
        model.send("hi")
        await settle(model)
        let expected = (0..<300).map { "w\($0) " }.joined()
        XCTAssertEqual(model.messages.last?.content, expected)
        // 300 deltas arrive in far less than a second: a handful of UI updates, not 300.
        XCTAssertLessThan(model.publishCount, 40)
    }

    func test_emptyReplyShowsNoResponse() async {
        let (model, _, _, _) = make(replay: [.done])
        model.send("hi")
        await settle(model)
        XCTAssertFalse(model.messages.last?.content.isEmpty ?? true)
        XCTAssertEqual(model.messages.last?.failed, true)
    }

    func test_networkErrorShowsMessageAndRetryResends() async {
        let (model, _, chat, _) = make(replay: [], thenFails: APIError.network)
        model.send("hi")
        await settle(model)
        XCTAssertEqual(model.messages.last?.failed, true)
        XCTAssertFalse(model.messages.last?.content.isEmpty ?? true)
        chat.onStream.replays([.delta("ok"), .done])
        model.retry()
        await settle(model)
        XCTAssertEqual(model.messages.map(\.content), ["hi", "ok"])
        XCTAssertEqual(chat.onStream.callCount, 2)
    }

    func test_emptyAndWhitespaceNeverSent() {
        let (model, _, chat, _) = make(replay: [.done])
        model.send("   ")
        XCTAssertEqual(chat.onStream.callCount, 0)
        XCTAssertTrue(model.messages.isEmpty)
    }

    func test_threadsOpenAndDelete() async {
        let (model, env, _, _) = make(replay: events("chat_qa"))
        model.send("first")
        await settle(model)
        let first = model.threadID
        model.newThread()
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNotEqual(model.threadID, first)
        model.open(first)
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.sessionContext["destination"].string, "Thailand")
        model.deleteThread(first)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNil(env.chatThreads.thread(first))
    }

    // MARK: - Resume and user switches

    private func seedGuestThread() async -> (MemoryFileStore, UUID) {
        let seed = MemoryFileStore()
        let store = ChatThreadStore(files: seed)
        await store.switchUser(nil)
        let thread = store.create(title: "Stored")
        store.append(["id": "m1", "role": "user", "content": "Tokyo in April?"], to: thread.id)
        await store.flushPersistence()
        return (seed, thread.id)
    }

    func test_resumeWaitsForTheThreadsToLoad() async {
        let (seed, storedID) = await seedGuestThread()
        let gated = ReadGateFileStore(seed)
        let env = AppEnvironment.fake(files: gated)
        let model = ChatModel(env: env, track: { _ in })

        let loading = Task { await env.chatThreads.switchUser(nil) }
        await gated.waitUntilReadStarted()
        model.resumeLatestIfFresh()
        model.syncWithStore()
        XCTAssertTrue(model.messages.isEmpty, "nothing to resume while the file is still being read")
        XCTAssertFalse(env.chatThreads.isReady)

        gated.open()
        await loading.value
        XCTAssertTrue(env.chatThreads.isReady)
        model.syncWithStore()
        XCTAssertEqual(model.threadID, storedID)
        XCTAssertEqual(model.messages.map(\.content), ["Tokyo in April?"])
    }

    func test_typedTextIsNotReplacedByAThreadThatLoadsLater() async {
        let (seed, storedID) = await seedGuestThread()
        let gated = ReadGateFileStore(seed)
        let fakes = FakeRepositories()
        fakes.chat.onStream.replays(events("chat_qa"), thenFails: nil)
        let env = AppEnvironment.fake(fakes: fakes, files: gated)
        let model = ChatModel(env: env, track: { _ in })

        let loading = Task { await env.chatThreads.switchUser(nil) }
        await gated.waitUntilReadStarted()
        model.send("typed first")
        await settle(model)
        let typedID = model.threadID
        gated.open()
        await loading.value
        model.syncWithStore()

        XCTAssertEqual(model.threadID, typedID)
        XCTAssertNotEqual(model.threadID, storedID)
        XCTAssertEqual(model.messages.first?.content, "typed first")
    }

    func test_switchingUserDropsThePreviousUsersConversation() async {
        let fakes = FakeRepositories()
        fakes.chat.onStream.replays(events("chat_qa"), thenFails: nil)
        let env = AppEnvironment.fake(fakes: fakes)
        let model = ChatModel(env: env, track: { _ in })

        await env.chatThreads.switchUser("amy")
        model.syncWithStore()
        model.send("amy's secret")
        await settle(model)
        let amysThread = model.threadID
        await env.chatThreads.flushPersistence()

        await env.chatThreads.switchUser("bob")
        model.syncWithStore()
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNotEqual(model.threadID, amysThread)
        await env.chatThreads.flushPersistence()
        XCTAssertTrue(env.chatThreads.threads.isEmpty, "Bob's store must not receive Amy's conversation")

        await env.chatThreads.switchUser("amy")
        model.syncWithStore()
        XCTAssertEqual(model.threadID, amysThread)
        XCTAssertEqual(model.messages.first?.content, "amy's secret")
    }
}

/// Holds every read until `open()`.
private final class ReadGateFileStore: FileStore, @unchecked Sendable {
    private let inner: MemoryFileStore
    private let lock = NSLock()
    private var isOpen = false
    private var readStarted = false

    init(_ inner: MemoryFileStore) { self.inner = inner }

    func open() { lock.withLock { isOpen = true } }

    func waitUntilReadStarted() async {
        while !lock.withLock({ readStarted }) { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func read(_ path: String) async throws -> Data? {
        lock.withLock { readStarted = true }
        while !lock.withLock({ isOpen }) { try await Task.sleep(for: .milliseconds(5)) }
        return try await inner.read(path)
    }

    func write(_ data: Data, to path: String) async throws { try await inner.write(data, to: path) }
    func remove(_ path: String) async throws { try await inner.remove(path) }
}
