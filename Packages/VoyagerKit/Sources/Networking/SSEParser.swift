import Foundation

public struct SSEMessage: Sendable, Equatable {
    public let data: String
    public init(data: String) { self.data = data }
}

/// Server-sent events as the backend emits them (Android `docs/Networking-and-SSE.md`): `data:` lines are
/// joined by `\n` and dispatched on a blank line; `:` comments and `event:`, `id:`, `retry:` are ignored;
/// a final event without its blank line is delivered by `finish()`.
public struct SSEParser: Sendable {
    private var splitter = SSELineSplitter()
    private var dataLines: [String] = []

    public init() {}

    public mutating func feed(_ byte: UInt8) -> SSEMessage? {
        splitter.feed(byte).flatMap { feed(line: $0) }
    }

    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [SSEMessage] {
        bytes.compactMap { feed($0) }
    }

    /// End of stream: flushes a partial last line and an event still open.
    public mutating func finish() -> SSEMessage? {
        let last = splitter.finish().flatMap { feed(line: $0) }
        return last ?? dispatch()
    }

    private mutating func feed(line: String) -> SSEMessage? {
        if line.isEmpty { return dispatch() }
        guard line.hasPrefix("data:") else { return nil } // comments, event:, id:, retry:, unknown fields
        let value = line.dropFirst(5)
        dataLines.append(String(value.first == " " ? value.dropFirst() : value))
        return nil
    }

    private mutating func dispatch() -> SSEMessage? {
        guard !dataLines.isEmpty else { return nil }
        defer { dataLines.removeAll() }
        return SSEMessage(data: dataLines.joined(separator: "\n"))
    }
}
