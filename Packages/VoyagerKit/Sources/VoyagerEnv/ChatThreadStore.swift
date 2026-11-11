import CryptoKit
import Foundation
import Observation
import VoyagerModel

/// One chat conversation. Chat history is client-side, as on the web (the server is stateless).
/// `messages` are the web's serialised message objects (`role`, `content`, `sections`, `suggestions`,
/// `planning`, `comprehensiveItinerary`, `tripMap`, ...), so the chat feature owns their shape.
public struct ChatThread: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [JSONValue]
    /// The `session_context` the server sent last; sent back with the next request.
    public var sessionContext: JSONValue
    public var lastSearchContext: JSONValue

    public init(
        id: UUID = UUID(), title: String? = nil, createdAt: Date = Date(), updatedAt: Date? = nil,
        messages: [JSONValue] = [], sessionContext: JSONValue = .object([:]), lastSearchContext: JSONValue = .null
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.messages = messages
        self.sessionContext = sessionContext
        self.lastSearchContext = lastSearchContext
    }
}

/// The signed-in user's chat threads, most recently updated first, stored per user in
/// `chat/<sha256(username)>.json` (debounced, written off the main actor). Nothing is read until
/// `switchUser(_:)`; the environment calls it after the first frame and whenever the user changes.
@MainActor @Observable
public final class ChatThreadStore {
    /// The web keeps the last 50 messages of a conversation.
    public nonisolated static let messageLimit = 50

    public private(set) var threads: [ChatThread] = []
    /// Whose threads these are (`nil` = signed out, the web's `guest`).
    public private(set) var username: String?

    @ObservationIgnored private let files: any FileStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let persistDelay: Duration
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var lastWrite: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0

    public init(files: any FileStore, persistDelay: Duration = .seconds(1), now: @escaping @Sendable () -> Date = { Date() }) {
        self.files = files
        self.persistDelay = persistDelay
        self.now = now
    }

    /// `chat/<hex sha256 of the username, or "guest">.json`: no user name in a file name.
    public nonisolated static func path(for username: String?) -> String {
        let digest = SHA256.hash(data: Data((username ?? "guest").utf8))
        return "chat/" + digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    public func thread(_ id: UUID) -> ChatThread? {
        threads.first { $0.id == id }
    }

    /// Starts a new, empty thread at the top.
    @discardableResult
    public func create(title: String? = nil) -> ChatThread {
        let thread = ChatThread(title: title, createdAt: now())
        threads.insert(thread, at: 0)
        schedulePersist()
        return thread
    }

    /// Appends `message` to thread `id` (creating the thread when it does not exist), keeps the last 50
    /// messages and moves the thread to the top.
    public func append(_ message: JSONValue, to id: UUID) {
        update(id) { $0.messages.append(message) }
    }

    /// Changes thread `id` in place (the last message while it streams, the session context, the title),
    /// creating it when it does not exist, then moves it to the top.
    public func update(_ id: UUID, _ change: (inout ChatThread) -> Void) {
        var thread = thread(id) ?? ChatThread(id: id, createdAt: now())
        change(&thread)
        if thread.messages.count > Self.messageLimit {
            thread.messages.removeFirst(thread.messages.count - Self.messageLimit)
        }
        thread.updatedAt = now()
        threads.removeAll { $0.id == id }
        threads.insert(thread, at: 0)
        schedulePersist()
    }

    public func delete(_ id: UUID) {
        threads.removeAll { $0.id == id }
        schedulePersist()
    }

    /// Shows `username`'s threads: writes the current user's pending changes, then reads the new user's file.
    public func switchUser(_ username: String?) async {
        if pendingWrite != nil { writeNow() }
        loadGeneration += 1
        let generation = loadGeneration
        self.username = username
        threads = []
        let files = files
        let path = Self.path(for: username)
        let loaded = await Task.detached(priority: .utility) { () -> [ChatThread] in
            guard let data = try? await files.read(path) else { return [] }
            return (try? Self.decoder.decode([ChatThread].self, from: data)) ?? []
        }.value
        guard generation == loadGeneration else { return }
        // Threads created while the file was loading stay on top.
        let created = threads
        let known = Set(created.map(\.id))
        threads = created + loaded.filter { !known.contains($0.id) }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Persistence

    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func schedulePersist() {
        pendingWrite?.cancel()
        let delay = persistDelay
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    private func writeNow() {
        pendingWrite?.cancel()
        pendingWrite = nil
        let snapshot = threads
        let path = Self.path(for: username)
        let files = files
        let previous = lastWrite
        lastWrite = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? Self.encoder.encode(snapshot) else { return }
            try? await files.write(data, to: path)
        }
    }

    /// Writes pending changes now and waits for every write.
    public func flushPersistence() async {
        if pendingWrite != nil { writeNow() }
        await lastWrite?.value
    }
}
