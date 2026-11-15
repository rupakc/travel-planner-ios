import Foundation
import Networking
import VoyagerData
import VoyagerModel

/// The one door to the Phase 4 routes. It never calls a route while `features.sharing` is below 1 (an older backend keeps
/// the legacy plan link, silently), and a 404 that says sharing is off or the route is missing turns the feature off for
/// the session instead of retrying (`/config` is cached 5 minutes server-side).
@MainActor
public final class SharesService {
    /// Thrown instead of calling a route whose flag is off.
    public struct Unavailable: Error, Equatable, Sendable {}

    private unowned let env: AppEnvironment
    private var degraded = false
    /// Cached cards live in temporary storage and are purged at sign-out and launch.
    public let cards: ShareCardStore

    public init(env: AppEnvironment, cards: ShareCardStore = .standard) {
        self.env = env
        self.cards = cards
    }

    public var isAvailable: Bool { !degraded && RemoteFeatures(config: env.clientConfig).hasSharingV2 }

    public func create(_ request: ShareRequest) async throws -> Share {
        try await run(.create) { try await $0.create(request) }
    }

    public func list() async throws -> ShareList {
        try await run(.list) { try await $0.list() }
    }

    public func revoke(token: String) async throws {
        try await run(.revoke) { try await $0.revoke(token: token) }
    }

    /// Downloads one of a share's cards when its host is trusted; nil URL means link only.
    public func cardLoader() -> any ShareCardLoading {
        let server = env.server
        return LiveShareCardLoader(store: cards, isTrusted: { server.trustsAsset($0) })
    }

    private func run<T>(_ call: ShareCall, _ operation: (any SharesRepository) async throws -> T) async throws -> T {
        guard isAvailable else { throw Unavailable() }
        do {
            return try await operation(env.repos.shares)
        } catch let error as APIError {
            if ShareFailure.isRouteMissing(error) || ShareFailure.from(error, call: call) == .sharingDisabled { degraded = true }
            throw error
        }
    }
}

/// The two card sizes of `GET /share/{token}/card.png`.
public enum ShareCardSize: String, Sendable, Hashable, CaseIterable {
    /// 1200x630, the link preview.
    case link
    /// 1080x1920, the story card ("Share image").
    case story
}

public enum ShareCardError: Error, Equatable, Sendable {
    /// The card URL is not on the backend or a trusted host: only the link is shared.
    case untrustedHost
    case badResponse
    case notAnImage
    case tooLarge
}

/// Downloads share cards. A failure never blocks sharing: the caller shares the link only.
public protocol ShareCardLoading: Sendable {
    /// The local PNG of `url` for `token`, or a `ShareCardError`/`CancellationError`.
    func load(_ url: URL, token: String, size: ShareCardSize) async throws -> URL
}

/// Cards and downloaded PNGs live in `NSTemporaryDirectory()/share-cards`; `purge()` empties it (sign-out, launch).
public struct ShareCardStore: Sendable {
    public let directory: URL

    public static let standard = ShareCardStore(
        directory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("share-cards", isDirectory: true))

    public init(directory: URL) {
        self.directory = directory
    }

    /// `<token>-<size>.png`; a token with anything but URL-safe characters is replaced by its hash so a name can never
    /// leave the directory.
    public func fileURL(token: String, size: ShareCardSize) -> URL {
        let safe = !token.isEmpty && token.count <= 64
            && token.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        let name = safe ? token : String(token.hashValue.magnitude, radix: 16)
        return directory.appendingPathComponent("\(name)-\(size.rawValue).png")
    }

    public func write(_ data: Data, token: String, size: ShareCardSize) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(token: token, size: size)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Removes every cached card. Safe when the directory does not exist.
    public func purge() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The live loader: the app's own ephemeral `URLSession`, no credentials, no cache, trusted hosts only.
public struct LiveShareCardLoader: ShareCardLoading {
    /// A story card is a few hundred KB; anything over this is not one.
    static let maxBytes = 8 * 1024 * 1024
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private let store: ShareCardStore
    private let session: URLSession
    private let isTrusted: @Sendable (URL) -> Bool

    public init(
        store: ShareCardStore, session: URLSession = URLSession(configuration: .ephemeral),
        isTrusted: @escaping @Sendable (URL) -> Bool
    ) {
        self.store = store
        self.session = session
        self.isTrusted = isTrusted
    }

    public func load(_ url: URL, token: String, size: ShareCardSize) async throws -> URL {
        guard isTrusted(url) else { throw ShareCardError.untrustedHost }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request, delegate: RedirectGuard(isTrusted: isTrusted))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ShareCardError.badResponse }
        guard data.count <= Self.maxBytes else { throw ShareCardError.tooLarge }
        guard data.starts(with: Self.pngSignature) else { throw ShareCardError.notAnImage }
        return try store.write(data, token: token, size: size)
    }
}

/// A redirect to a host that is not trusted ends the download (the card route never redirects).
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let isTrusted: @Sendable (URL) -> Bool

    init(isTrusted: @escaping @Sendable (URL) -> Bool) {
        self.isTrusted = isTrusted
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, isTrusted(url) else { return nil }
        return request
    }
}

/// The error codes of `Sharing-API.md` that clients translate. Everything else keeps the backend `detail`.
public enum ShareFailure: String, Error, Sendable, Hashable, CaseIterable {
    case sharingDisabled = "sharing_disabled"
    case planNotFound = "plan_not_found"
    case invalidKind = "invalid_kind"
    case shareNotFound = "share_not_found"
    case sessionNotFound = "session_not_found"
    case playDisabled = "play_disabled"
    case noActiveTrip = "no_active_trip"
    case cardBusy = "card_busy"

    /// The translated failure of `error`, or nil (429, a network error, an unknown code, a route that is missing).
    ///
    /// `ErrorMapping` keeps only the `detail` of a 404, so a 404's code is read from the envelope's fixed text
    /// ("Sharing is not available.", "Plan not found.", "Quiz session not found.", "Play is not available.",
    /// "Share not found."). A bare FastAPI `Not Found` is a missing route, not one of ours.
    public static func from(_ error: APIError, call: ShareCall) -> ShareFailure? {
        switch error {
        case .client(_, _, let code, let body):
            let raw = code ?? body["error_code"].string ?? body["detail"]["error_code"].string
            return raw.flatMap(ShareFailure.init(rawValue:))
        case .notFound(let detail):
            return fromNotFound(detail: detail, call: call)
        case .server(_, _, let code):
            return code.flatMap(ShareFailure.init(rawValue:))
        default:
            return nil
        }
    }

    /// A 404 that is the route itself missing (FastAPI's `Not Found`, or no text at all).
    public static func isRouteMissing(_ error: APIError) -> Bool {
        if case .notFound(let detail) = error { return detail == nil || detail == "Not Found" }
        return false
    }

    private static func fromNotFound(detail: String?, call: ShareCall) -> ShareFailure? {
        guard let text = detail?.lowercased(), text != "not found" else { return nil }
        if text.contains("sharing") { return .sharingDisabled }
        if text.contains("session") { return .sessionNotFound }
        if text.contains("play") { return .playDisabled }
        if text.contains("plan") { return .planNotFound }
        if text.contains("share") { return .shareNotFound }
        return call == .revoke ? .shareNotFound : nil
    }
}

/// Which share call failed: a 404 means something different for each.
public enum ShareCall: Sendable, Hashable {
    case create, list, revoke
}
