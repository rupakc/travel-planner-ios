import Foundation
import VoyagerEnv
import VoyagerModel

/// Maps an incoming URL (custom scheme, universal link, push or notification link) to a `Route`.
/// Anything else is nil: unknown hosts, unknown paths, malformed ids.
public enum DeepLinks {
    public static let scheme = "voyager"

    /// With the app's trusted hosts (`AppBuildConfig.trustedHosts`).
    @MainActor
    public static func route(for url: URL, env: AppEnvironment) -> Route? {
        route(for: url, trustedHosts: env.build.trustedHosts)
    }

    /// `voyager://share/<token>`, `https://<trusted host>/share/<token>`, `/alerts?watch=<id>`,
    /// `/alerts?kind=<k>&watch=<id>`, `/trips/{id}`, `/trips/{id}/today`, `/feed`, `/feed/{id}`, `/u/{handle}`,
    /// `/play`, `/play/h2h/{id}` and `voyager://import?url=<url>`.
    public static func route(for url: URL, trustedHosts: Set<String>) -> Route? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let query = queryItems(url)
        let parts = url.pathComponents.filter { $0 != "/" }
        switch scheme {
        case Self.scheme:
            // The host is the first segment: voyager://share/<token>.
            return route(segments: [host] + parts, query: query, custom: true)
        case "https":
            guard trustedHosts.map({ $0.lowercased() }).contains(host) else { return nil }
            return route(segments: parts, query: query, custom: false)
        default:
            return nil
        }
    }

    private static func route(segments: [String], query: [String: String], custom: Bool) -> Route? {
        guard let head = segments.first else { return nil }
        let rest = Array(segments.dropFirst())
        switch head {
        case "share":
            guard rest.count == 1, validToken(rest[0]) else { return nil }
            return .share(token: rest[0])
        case "alerts":
            guard rest.isEmpty else { return nil }
            var kind: WatchKind?
            if let raw = query["kind"] {
                guard let parsed = WatchKind(rawValue: raw) else { return nil }
                kind = parsed
            }
            var watchID: Int?
            if let raw = query["watch"] {
                guard let parsed = Int(raw), parsed > 0 else { return nil }
                watchID = parsed
            }
            return .alerts(kind: kind, watchID: watchID)
        case "trips":
            // /trips/{id} is the trip detail, /trips/{id}/today its Today view.
            guard let id = positiveInt(rest.first), rest.count <= 2 else { return nil }
            if rest.count == 1 { return .planDetail(id: id) }
            return rest[1] == "today" ? .tripToday(planID: id) : nil
        case "feed":
            if rest.isEmpty { return .ideas }
            guard rest.count == 1, validToken(rest[0]) else { return nil }
            return .ideaDetail(id: rest[0])
        case "u":
            guard rest.count == 1, validHandle(rest[0]) else { return nil }
            return .profile(handle: rest[0])
        case "play":
            if rest.isEmpty { return .play }
            guard rest.count == 2, rest[0] == "h2h", validToken(rest[1]) else { return nil }
            return .h2h(id: rest[1])
        case "import":
            // Only the app's own scheme imports; a web link must not start an import.
            guard custom, rest.isEmpty else { return nil }
            guard let raw = query["url"] else { return .importLink(nil) }
            guard let target = URL(string: raw), let scheme = target.scheme?.lowercased(),
                scheme == "http" || scheme == "https", target.host != nil
            else { return nil }
            return .importLink(target)
        default:
            return nil
        }
    }

    /// A server notification `link` (a web path such as `/trips/7/today`), mapped through the same allow-list.
    /// Only a bare path is accepted: a scheme, a host, `//host`, a fragment-less oddity or an unknown path is nil,
    /// so a link is never opened raw.
    public static func route(forNotificationLink link: String) -> Route? {
        guard link.hasPrefix("/"), !link.hasPrefix("//"), !link.contains("\\"), link.count <= 256,
            let components = URLComponents(string: link), components.scheme == nil, components.host == nil
        else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        guard !parts.contains(where: \.isEmpty) || parts == [""] else { return nil }
        let segments = parts == [""] ? [] : parts
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            if let value = item.value { query[item.name] = value }
        }
        return route(segments: segments, query: query, custom: false)
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var result: [String: String] = [:]
        for item in items {
            if let value = item.value, result[item.name] == nil { result[item.name] = value }
        }
        return result
    }

    private static func positiveInt(_ text: String?) -> Int? {
        guard let text, text.count <= 12, text.allSatisfy(\.isASCII), let value = Int(text), value > 0 else { return nil }
        return value
    }

    /// Handles are short ASCII names (letters, digits, `_`, `.`, `-`).
    static func validHandle(_ handle: String) -> Bool {
        guard (1...32).contains(handle.count) else { return false }
        return handle.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "_.-".unicodeScalars.contains(scalar))
        }
    }

    /// Share tokens are URL-safe random strings; anything else is not a share link.
    static func validToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 128 else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        }
    }
}
