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
}
