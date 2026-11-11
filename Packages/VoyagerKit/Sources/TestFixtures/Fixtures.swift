import Foundation

/// Shared test fixtures under `Packages/VoyagerKit/Tests/Fixtures/`, resolved from `#filePath`
/// (the iOS simulator can read host paths), so test targets need no bundled resources.
public enum Fixtures {
    public struct NotFound: Error, CustomStringConvertible {
        public let path: String
        public var description: String { "Fixture not found: \(path)" }
    }

    /// The fixtures directory: `Tests/Fixtures` next to `Sources/`.
    public static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TestFixtures
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // VoyagerKit
        .appendingPathComponent("Tests/Fixtures", isDirectory: true)

    /// The URL of `name`, a path relative to the fixtures directory (`"sse/search_full.sse"`).
    public static func url(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    public static func data(_ name: String) throws -> Data {
        let url = url(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw NotFound(path: url.path) }
        return try Data(contentsOf: url)
    }

    public struct NotUTF8: Error, CustomStringConvertible {
        public let name: String
        public var description: String { "Fixture is not UTF-8: \(name)" }
    }

    public static func string(_ name: String) throws -> String {
        guard let text = String(bytes: try data(name), encoding: .utf8) else { throw NotUTF8(name: name) }
        return text
    }

    /// The payload of every `data:` line of an `.sse` fixture, in order (comments and blank lines skipped).
    public static func sseDataLines(_ name: String) throws -> [String] {
        try string(name)
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard line.hasPrefix("data:") else { return nil }
                let payload = line.dropFirst(5)
                return String(payload.first == " " ? payload.dropFirst() : payload)
            }
    }
}
