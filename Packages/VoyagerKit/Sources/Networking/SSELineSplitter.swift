import Foundation

/// Splits a byte stream into lines on `\n`, `\r\n` and `\r`, keeping empty lines
/// (`AsyncBytes.lines` drops them, and a blank line is what dispatches an SSE event).
/// Bytes are buffered per line, so multi-byte UTF-8 characters split across chunks stay intact.
struct SSELineSplitter {
    private var buffer: [UInt8] = []
    private var skipLineFeed = false

    /// Feeds one byte. A byte completes at most one line.
    mutating func feed(_ byte: UInt8) -> String? {
        if skipLineFeed {
            skipLineFeed = false
            if byte == 0x0A { return nil }
        }
        switch byte {
        case 0x0A:
            return takeLine()
        case 0x0D:
            skipLineFeed = true
            return takeLine()
        default:
            buffer.append(byte)
            return nil
        }
    }

    /// The unterminated last line at end of stream, if any.
    mutating func finish() -> String? {
        buffer.isEmpty ? nil : takeLine()
    }

    private mutating func takeLine() -> String {
        defer { buffer.removeAll(keepingCapacity: true) }
        // Lossy on purpose: one invalid byte must not drop the whole line.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: buffer, as: UTF8.self)
    }
}
