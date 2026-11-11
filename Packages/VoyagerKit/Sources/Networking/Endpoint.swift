import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public enum AuthMode: Sendable, Equatable {
    /// Never sends a token.
    case none
    /// Sends the token when signed in, goes anonymous otherwise.
    case optional
    /// Needs a token; signed out fails with `.unauthorized` without a request.
    case required
}

/// The response type of a 204 / empty-body call.
public struct Empty: Decodable, Sendable, Equatable {
    public init() {}
    public init(from decoder: any Decoder) throws {}
}

public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var query: [URLQueryItem]
    public var body: (any Encodable & Sendable)?
    public var auth: AuthMode
    public var timeout: TimeoutClass
    /// Route template such as `/api/plans/:id`; this, never the concrete path, goes to telemetry.
    public var telemetryName: String

    public init(
        method: HTTPMethod = .get,
        path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        auth: AuthMode = .required,
        timeout: TimeoutClass = .standard,
        telemetryName: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.auth = auth
        self.timeout = timeout
        self.telemetryName = telemetryName ?? path
    }
}

/// Type-erases an `Encodable` existential for `JSONEncoder`.
struct AnyEncodable: Encodable {
    let value: any Encodable
    func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}

/// Builds `URLRequest`s for both `APIClient` and `SSEClient`.
enum RequestFactory {
    static func url(base: URL, path: String, query: [URLQueryItem]) throws -> URL {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw APIError.notConfigured }
        var prefix = comps.path
        while prefix.hasSuffix("/") { prefix.removeLast() }
        comps.path = prefix + (path.hasPrefix("/") ? path : "/" + path)
        comps.queryItems = query.isEmpty ? nil : query
        // URLComponents leaves "+" literal in a query, which servers read as a space.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = comps.url else { throw APIError.notConfigured }
        return url
    }

    static func request(
        base: URL, method: HTTPMethod, path: String, query: [URLQueryItem] = [],
        body: (any Encodable)?, token: String?, timeout: TimeInterval, accept: String
    ) throws -> URLRequest {
        var request = URLRequest(url: try url(base: base, path: path, query: query))
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(AnyEncodable(value: body))
            } catch {
                throw APIError.decoding
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }
}
