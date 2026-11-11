import Foundation

/// Bounded FIFO with O(1) amortised append and drop-oldest at `capacity`.
struct EventBuffer: Sendable {
    static let capacity = 500

    private var items: [StoredEvent] = []
    private var head = 0

    var count: Int { items.count - head }
    var isEmpty: Bool { count == 0 }
    var all: [StoredEvent] { Array(items[head...]) }

    mutating func append(_ event: StoredEvent) {
        items.append(event)
        if count > Self.capacity { head += 1 }
        if head >= Self.capacity { compact() }
    }

    /// Takes up to `limit` events from the front that share the first event's session.
    mutating func popBatch(limit: Int) -> [StoredEvent] {
        guard head < items.count else { return [] }
        let session = items[head].session
        var end = head
        while end < items.count, end - head < limit, items[end].session == session { end += 1 }
        let batch = Array(items[head..<end])
        head = end
        compact()
        return batch
    }

    /// Puts events back in front of the queue; if that overflows, the oldest are dropped.
    mutating func pushFront(_ events: [StoredEvent]) {
        var merged = events + all
        if merged.count > Self.capacity { merged.removeFirst(merged.count - Self.capacity) }
        items = merged
        head = 0
    }

    mutating func removeAll() {
        items = []
        head = 0
    }

    private mutating func compact() {
        guard head > 0 else { return }
        items.removeFirst(head)
        head = 0
    }
}
