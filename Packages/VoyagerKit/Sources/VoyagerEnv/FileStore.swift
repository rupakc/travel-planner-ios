import Foundation

/// Small files the app keeps for itself (the current plan, chat threads). Paths are relative
/// (`current-plan.json`, `chat/<hash>.json`). Every call runs off the main actor.
public protocol FileStore: Sendable {
    /// The file's bytes, or nil when it does not exist.
    func read(_ path: String) async throws -> Data?
    /// Writes atomically, creating intermediate directories.
    func write(_ data: Data, to path: String) async throws
    func remove(_ path: String) async throws
}

/// A `FileStore` under a directory on disk (by default `Application Support`).
public struct DiskFileStore: FileStore {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// `<Application Support>` of the app's container. Computing the URL does no I/O.
    public static func applicationSupport() -> DiskFileStore {
        DiskFileStore(root: URL.applicationSupportDirectory)
    }

    public func read(_ path: String) async throws -> Data? {
        let url = root.appendingPathComponent(path)
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        }.value
    }

    public func write(_ data: Data, to path: String) async throws {
        let url = root.appendingPathComponent(path)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        }.value
    }

    public func remove(_ path: String) async throws {
        let url = root.appendingPathComponent(path)
        try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        }.value
    }
}
