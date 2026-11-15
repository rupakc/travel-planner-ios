import Foundation

/// The token of a pasted share link. Only the app's own `voyager://share/<token>` and `https://<trusted host>/share/<token>`
/// count (the same allow-list as `DeepLinks`); anything else is nil, so a pasted link is never opened raw.
enum ShareLinkParser {
    static func token(from url: URL, trustedHosts: Set<String>) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let segments: [String]
        switch scheme {
        case "voyager":
            segments = [host] + parts
        case "https":
            guard trustedHosts.contains(where: { $0.lowercased() == host }) else { return nil }
            segments = parts
        default:
            return nil
        }
        guard segments.count == 2, segments[0] == "share", isValid(segments[1]) else { return nil }
        return segments[1]
    }

    /// The token of a share URL the server returned (`<base>/share/<token>`), for "Open" on a legacy row.
    static func token(fromServerURL text: String) -> String? {
        guard let url = URL(string: text) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[parts.count - 2] == "share", isValid(parts[parts.count - 1]) else { return nil }
        return parts[parts.count - 1]
    }

    /// 8 to 64 URL-safe characters (`Sharing-API.md`).
    static func isValid(_ token: String) -> Bool {
        guard (8...64).contains(token.count) else { return false }
        return token.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }
}
