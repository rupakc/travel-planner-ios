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
    /// True once `username`'s file was read successfully; false before the first `switchUser(_:)` and while a
    /// switch or a retried read is pending. Observers (the chat screen) resume the latest thread when it flips.
    public private(set) var isReady = false
    /// True once a `switchUser(_:)` has begun, i.e. `username` is a real answer and not just the initial `nil`.
    public private(set) var hasSwitched = false

    @ObservationIgnored private let files: any FileStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let persistDelay: Duration
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var lastWrite: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    /// `threads` hold the whole of `username`'s file (or the load failed benignly). Nothing is written before
    /// that: a partial list must never replace the stored one.
    @ObservationIgnored private var loaded = true
    @ObservationIgnored private var switchTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Threads made for a user whose file was never read (so they could not be written) before another user was
    /// shown; merged into that user's threads when their file is next read.
    @ObservationIgnored private var orphans: [String: [ChatThread]] = [:]

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
    /// Switches run one after another, so an earlier load always finishes (and keeps its changes) first.
    public func switchUser(_ username: String?) async {
        let previous = switchTask
        let task = Task { [weak self] in
            await previous?.value
            await self?.performSwitch(username)
        }
        switchTask = task
        await task.value
    }

    private func performSwitch(_ username: String?) async {
        if pendingWrite != nil { writeNow() }
        // The read must not overtake a write to the same file (same user signing out and straight back in).
        await lastWrite?.value
        retryTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        if !loaded, !threads.isEmpty { orphans[Self.path(for: self.username), default: []] += threads }
        loaded = false
        isReady = false
        self.username = username
        hasSwitched = true
        threads = []
        if await attemptLoad(generation: generation) == false { scheduleLoadRetry(generation: generation) }
    }

    private enum LoadResult: Sendable {
        case threads([ChatThread])
        case unreadable(Data)
        case failed
    }

    /// Reads the current user's file. Returns false when the read threw (locked file, I/O error): that is not
    /// "no file", so `loaded` stays false (writes stay blocked) until a later read succeeds.
    private func attemptLoad(generation: Int) async -> Bool {
        let files = files
        let path = Self.path(for: username)
        let result = await Task.detached(priority: .utility) { () -> LoadResult in
            let data: Data?
            do { data = try await files.read(path) } catch { return .failed }
            guard let data else { return .threads([]) }
            guard let threads = try? Self.decoder.decode([ChatThread].self, from: data) else { return .unreadable(data) }
            return .threads(threads)
        }.value
        guard generation == loadGeneration else { return true }
        var stored: [ChatThread] = []
        switch result {
        case .failed: return false
        case .unreadable(let bytes):
            // E.g. a newer schema: keep the bytes before the next write replaces the file.
            try? await files.write(bytes, to: path + ".bak")
        case .threads(let threads): stored = threads
        }
        guard generation == loadGeneration else { return true }
        // Threads created while the file was loading stay on top.
        var created: [ChatThread] = []
        for thread in threads + (orphans.removeValue(forKey: path) ?? []) where !created.contains(where: { $0.id == thread.id }) {
            created.append(thread)
        }
        let known = Set(created.map(\.id))
        let older = stored.filter { !known.contains($0.id) }.sorted { $0.updatedAt > $1.updatedAt }
        threads = created + older
        loaded = true
        isReady = true
        if !created.isEmpty { schedulePersist() }
        return true
    }

    private func scheduleLoadRetry(generation: Int) {
        retryTask?.cancel()
        let delay = persistDelay
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, generation == self.loadGeneration else { return }
                if await self.attemptLoad(generation: generation) { return }
            }
        }
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
        guard loaded else { return }
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
        await switchTask?.value
        if pendingWrite != nil { writeNow() }
        await lastWrite?.value
    }
}
