import DesignSystem
import Foundation
import SwiftUI

/// Parsed markdown, kept per text so a message is parsed once (not on every redraw).
enum MarkdownCache {
    /// Messages over this size are parsed off the main actor.
    static let largeBytes = 2048

    private final class Box: @unchecked Sendable {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    private nonisolated(unsafe) static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 200
        return cache
    }()

    nonisolated static func cached(_ text: String) -> AttributedString? {
        cache.object(forKey: text as NSString)?.value
    }

    /// Inline markdown with line breaks kept; text that is not valid markdown is shown as it is.
    nonisolated static func parse(_ text: String) -> AttributedString {
        if let hit = cached(text) { return hit }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let value = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        cache.setObject(Box(value), forKey: text as NSString)
        return value
    }

    static func parseOffMain(_ text: String) async -> AttributedString {
        await Task.detached(priority: .userInitiated) { parse(text) }.value
    }
}

/// An assistant message's text. While it streams it is plain text (cheap, no reparse per delta); once finished
/// it is parsed once as markdown (off the main actor when over 2 KB).
struct MarkdownText: View {
    let text: String
    let finished: Bool
    @State private var parsed: AttributedString?

    var body: some View {
        Group {
            if !finished {
                Text(verbatim: text)
            } else if let ready = MarkdownCache.cached(text) ?? parsed {
                Text(ready)
            } else if text.utf8.count <= MarkdownCache.largeBytes {
                Text(MarkdownCache.parse(text))
            } else {
                Text(verbatim: text)
            }
        }
        .font(VFont.body(.body))
        .foregroundStyle(SemanticColor.text)
        .tint(SemanticColor.primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: finished ? text : nil) {
            guard finished, text.utf8.count > MarkdownCache.largeBytes, MarkdownCache.cached(text) == nil else { return }
            parsed = await MarkdownCache.parseOffMain(text)
        }
    }
}
