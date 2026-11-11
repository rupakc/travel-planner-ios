import Foundation
import os

public enum ServerEnvironmentError: Error, Sendable, Equatable {
    case overrideNotAllowed
    case invalidURL
    /// Plain `http` is only for localhost, 127.0.0.1, `*.local` and private (RFC 1918) addresses.
    case insecureHost
}

/// The effective backend base URL: Debug override > adopted public URL > build setting.
public final class ServerEnvironment: Sendable {
    static let overrideKey = "voyager.server.override"
    static let adoptedKey = "voyager.server.adopted"

    private struct State {
        var override: URL?
        var adopted: URL?
    }

    private let buildBaseURL: URL?
    private let trustedHosts: Set<String>
    private let allowsOverride: Bool
    /// `UserDefaults` is documented thread-safe but not `Sendable` in every SDK, so it lives in a lock
    /// (uncheckedState) that also serialises our writes.
    private let defaults: OSAllocatedUnfairLock<UserDefaults>
    private let state: OSAllocatedUnfairLock<State>

    public init(buildBaseURL: URL?, trustedHosts: Set<String>, allowsOverride: Bool, defaults: UserDefaults) {
        let hosts = Set(trustedHosts.map { $0.lowercased() })
        self.buildBaseURL = buildBaseURL
        self.trustedHosts = hosts
        self.allowsOverride = allowsOverride
        self.defaults = OSAllocatedUnfairLock(uncheckedState: defaults)
        let override = allowsOverride
            ? defaults.string(forKey: Self.overrideKey).flatMap(URL.init(string:)).flatMap { try? Self.validated($0) }
            : nil
        let adopted = defaults.string(forKey: Self.adoptedKey).flatMap(URL.init(string:))
            .flatMap { Self.isTrusted($0, hosts: hosts) ? $0 : nil }
        self.state = OSAllocatedUnfairLock(initialState: State(override: override, adopted: adopted))
    }

    /// Nil means "not configured": every call throws `APIError.notConfigured`.
    public var baseURL: URL? {
        state.withLock { $0.override ?? $0.adopted } ?? buildBaseURL
    }

    /// Debug only. `nil` clears the override.
    public func setOverride(_ url: URL?) throws {
        guard allowsOverride else { throw ServerEnvironmentError.overrideNotAllowed }
        let valid = try url.map(Self.validated)
        state.withLock { $0.override = valid }
        let text = valid?.absoluteString
        defaults.withLock { $0.set(text, forKey: Self.overrideKey) }
    }

    /// Switches to the server-advertised public URL, only when it is https and its host is trusted.
    public func adopt(publicBaseURL: URL) {
        guard Self.isTrusted(publicBaseURL, hosts: trustedHosts) else { return }
        state.withLock { $0.adopted = publicBaseURL }
        let text = publicBaseURL.absoluteString
        defaults.withLock { $0.set(text, forKey: Self.adoptedKey) }
    }

    private static func isTrusted(_ url: URL, hosts: Set<String>) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    private static func validated(_ url: URL) throws -> URL {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else {
            throw ServerEnvironmentError.invalidURL
        }
        switch scheme {
        case "https": return url
        case "http":
            guard isLocalHost(host) else { throw ServerEnvironmentError.insecureHost }
            return url
        default: throw ServerEnvironmentError.invalidURL
        }
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 != nil && (0...255).contains($0 ?? -1) }) else { return false }
        let octets = parts.compactMap { $0 }
        return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }
}
