import Foundation

/// `{{name}}` interpolation and the tiny `<tag>` markup of the web catalogue, as pure functions.
enum MarkupString {
    /// Replaces each `{{name}}` with `args[name]` in one pass (values are never re-scanned).
    /// An unknown placeholder stays as written.
    static func interpolate(_ template: String, _ args: [String: String]) -> String {
        guard !args.isEmpty, template.contains("{{") else { return template }
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "}}") else {
                out += rest[open.lowerBound...]
                return out
            }
            let name = afterOpen[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if let value = args[name] {
                out += value
            } else {
                out += rest[open.lowerBound..<close.upperBound]
            }
            rest = afterOpen[close.upperBound...]
        }
        out += rest
        return out
    }

    private struct OpenTag {
        let name: String
        let bold: Bool
        let link: URL?
    }

    enum Token: Equatable {
        case text(String)
        case open(name: String, href: String?)
        case close(name: String)
        case selfClosing(name: String)
    }

    /// Splits a template into text and tags. A `<` that does not start a well-formed tag
    /// (`<name>`, `</name>`, `<name/>`, `<a href="…">`) is literal text.
    static func tokenize(_ template: String) -> [Token] {
        var tokens: [Token] = []
        var text = ""
        var index = template.startIndex
        while index < template.endIndex {
            let char = template[index]
            if char == "<", let (token, next) = parseTag(template, from: index) {
                if !text.isEmpty {
                    tokens.append(.text(text))
                    text = ""
                }
                tokens.append(token)
                index = next
            } else {
                text.append(char)
                index = template.index(after: index)
            }
        }
        if !text.isEmpty { tokens.append(.text(text)) }
        return tokens
    }

    private static func parseTag(_ template: String, from start: String.Index) -> (Token, String.Index)? {
        guard let end = template[start...].firstIndex(of: ">") else { return nil }
        var body = template[template.index(after: start)..<end]
        let closing = body.first == "/"
        if closing { body = body.dropFirst() }
        let selfClosing = body.last == "/"
        if selfClosing { body = body.dropLast() }
        let name = body.prefix { $0.isLetter || $0.isNumber }
        guard let first = name.first, first.isLetter else { return nil }
        let attributes = body.dropFirst(name.count)
        guard attributes.isEmpty || attributes.first?.isWhitespace == true else { return nil }
        let after = template.index(after: end)
        let tag = String(name)
        if closing { return attributes.allSatisfy(\.isWhitespace) ? (.close(name: tag), after) : nil }
        if selfClosing { return (.selfClosing(name: tag), after) }
        return (.open(name: tag, href: href(in: attributes)), after)
    }

    private static func href(in attributes: Substring) -> String? {
        guard let range = attributes.range(of: "href=\"") else { return nil }
        let rest = attributes[range.upperBound...]
        guard let quote = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<quote])
    }

    /// Builds an `AttributedString`: `<strong>`/`<b>` bold, `<a href>` (https/http only) and any tag named
    /// in `links` a link, every other tag dropped with its text kept. `{{name}}` is filled per text run,
    /// after parsing, so argument values can never inject markup.
    static func attributed(_ template: String, _ args: [String: String], links: [String: URL]) -> AttributedString {
        var result = AttributedString()
        var stack: [OpenTag] = []
        for token in tokenize(template) {
            switch token {
            case .text(let raw):
                var run = AttributedString(interpolate(raw, args))
                if stack.contains(where: \.bold) { run.inlinePresentationIntent = .stronglyEmphasized }
                if let link = stack.last(where: { $0.link != nil })?.link { run.link = link }
                result.append(run)
            case .open(let name, let href):
                let isBold = name == "strong" || name == "b"
                let url = links[name] ?? (name == "a" ? safeURL(href) : nil)
                stack.append(OpenTag(name: name, bold: isBold, link: url))
            case .close(let name):
                if let at = stack.lastIndex(where: { $0.name == name }) { stack.remove(at: at) }
            case .selfClosing:
                break
            }
        }
        return result
    }

    private static func safeURL(_ href: String?) -> URL? {
        guard let href, let url = URL(string: href), ["https", "http"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
    }
}
