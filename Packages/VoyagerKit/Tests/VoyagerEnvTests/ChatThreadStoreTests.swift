import Foundation
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@MainActor
@Suite struct ChatThreadStoreTests {
    @Test func test_perUserIsolation() async throws {
        let files = MemoryFileStore()
        let store = ChatThreadStore(files: files)

        await store.switchUser("amy")
        let amys = store.create()
        store.append(["role": "user", "content": "Tokyo in April?"], to: amys.id)
        await store.flushPersistence()

        await store.switchUser("bob")
        #expect(store.threads.isEmpty)
        #expect(store.username == "bob")
        let bobs = store.create()
        store.append(["role": "user", "content": "Lisbon food"], to: bobs.id)
        await store.flushPersistence()

        await store.switchUser("amy")
        #expect(store.threads.map(\.id) == [amys.id])
        #expect(store.thread(amys.id)?.messages == [["role": "user", "content": "Tokyo in April?"]])
        #expect(store.thread(bobs.id) == nil)

        // One file per user, named by a hash (no user name on disk).
        let amyPath = ChatThreadStore.path(for: "amy")
        let bobPath = ChatThreadStore.path(for: "bob")
        #expect(amyPath != bobPath)
        #expect(Set(files.files.keys) == [amyPath, bobPath])
        #expect(!amyPath.contains("amy"))
        #expect(amyPath.hasPrefix("chat/") && amyPath.hasSuffix(".json"))

        // A fresh store (relaunch) reads the same user's threads back.
        let relaunched = ChatThreadStore(files: files)
        await relaunched.switchUser("amy")
        #expect(relaunched.threads.map(\.id) == [amys.id])

        relaunched.delete(amys.id)
        #expect(relaunched.threads.isEmpty)
    }

    @Test func test_keepsLast50Messages() {
        let store = ChatThreadStore(files: MemoryFileStore())
        let thread = store.create()
        for index in 0..<60 { store.append(["role": "user", "content": .string("m\(index)")], to: thread.id) }
        let messages = store.thread(thread.id)?.messages ?? []
        #expect(messages.count == ChatThreadStore.messageLimit)
        #expect(messages.first?["content"] == "m10")
    }

    @Test func test_switchWhileLoadingDoesNotOverwriteStoredThreads() async throws {
        let seed = MemoryFileStore()
        let earlier = ChatThreadStore(files: seed)
        await earlier.switchUser("amy")
        let old = earlier.create(title: "Old")
        await earlier.flushPersistence()

        let gated = GatedFileStore(seed)
        let store = ChatThreadStore(files: gated)
        let first = Task { await store.switchUser("amy") }
        await gated.waitUntilReadStarted()
        let fresh = store.create(title: "Fresh") // a write is pending while Amy's file is still loading
        let second = Task { await store.switchUser("bob") }
        gated.open()
        await first.value
        await second.value
        await store.flushPersistence()

        let amy = try #require(try await seed.read(ChatThreadStore.path(for: "amy")))
        let stored = try JSONDecoder.iso.decode([ChatThread].self, from: amy)
        #expect(Set(stored.map(\.id)) == [old.id, fresh.id])
        #expect(store.username == "bob")
        #expect(store.threads.isEmpty)
    }

    @Test func test_sameUserBackToBackReadsAfterWrite() async {
        let files = MemoryFileStore()
        let store = ChatThreadStore(files: files)
        await store.switchUser("amy")
        let thread = store.create()
        await store.switchUser(nil)
        await store.switchUser("amy")
        #expect(store.threads.map(\.id) == [thread.id])
    }

    @Test func test_unreadableFileIsKeptAsBackup() async throws {
        let garbage = Data(#"{"version": 99}"#.utf8)
        let path = ChatThreadStore.path(for: "amy")
        let files = MemoryFileStore(files: [path: garbage])
        let store = ChatThreadStore(files: files)
        await store.switchUser("amy")
        #expect(store.threads.isEmpty)
        store.create()
        await store.flushPersistence()
        #expect(files.files[path + ".bak"] == garbage)
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Holds every read until `open()`.
private final class GatedFileStore: FileStore, @unchecked Sendable {
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
