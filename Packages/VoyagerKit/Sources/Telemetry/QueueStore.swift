import Foundation

/// The offline queue file, `<storeDirectory>/tq.json`. Every failure is swallowed: telemetry never throws.
struct QueueStore: Sendable {
    static let maxAge: TimeInterval = 7 * 24 * 3600

    let directory: URL
    var file: URL { directory.appendingPathComponent("tq.json") }

    func save(_ events: [StoredEvent]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: file, options: .atomic)
        } catch {
            // Disk full or read-only: the events stay in memory only.
        }
    }

    /// Reads and removes the file; events older than 7 days are discarded.
    func claim(now: Date) -> [StoredEvent] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        try? FileManager.default.removeItem(at: file)
        let cutoff = Int64((now.timeIntervalSince1970 - Self.maxAge) * 1000)
        let events = (try? JSONDecoder().decode([StoredEvent].self, from: data)) ?? []
        return events.filter { $0.ts >= cutoff }
    }

    func clear() {
        try? FileManager.default.removeItem(at: file)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: file.path) }
}
