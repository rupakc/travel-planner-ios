import Foundation
import VoyagerModel

public actor APIClient {
    private let server: ServerEnvironment
    private let tokens: any AccessTokenProvider
    private let session: URLSession
    private let observer: (any APIObserver)?

    public init(
        server: ServerEnvironment,
        tokens: any AccessTokenProvider,
        session: URLSession = .shared,
        observer: (any APIObserver)? = nil
    ) {
        self.server = server
        self.tokens = tokens
        self.session = session
        self.observer = observer
    }

    /// Sends `endpoint`; JSON decoding runs inside this actor, never on the main actor.
    public func send<R>(_ endpoint: Endpoint<R>) async throws -> R {
        let (data, _) = try await execute(endpoint)
        if let empty = Empty() as? R { return empty }
        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            // Includes an HTML 200 from a captive portal.
            throw APIError.decoding
        }
    }

    /// Like `send` for open-ended JSON, also returning the response (headers).
    public func raw(_ endpoint: Endpoint<JSONValue>) async throws -> (JSONValue, HTTPURLResponse) {
        let (data, response) = try await execute(endpoint)
        do {
            return (try JSONDecoder().decode(JSONValue.self, from: data), response)
        } catch {
            throw APIError.decoding
        }
    }

    private func execute<R>(_ endpoint: Endpoint<R>) async throws -> (Data, HTTPURLResponse) {
        guard let base = server.baseURL else { throw APIError.notConfigured }
        var retried = false
        while true {
            let token = endpoint.auth == .none ? nil : await tokens.currentToken()
            if endpoint.auth == .required, token == nil { throw APIError.unauthorized }
            let request = try RequestFactory.request(
                base: base, method: endpoint.method, path: endpoint.path, query: endpoint.query,
                body: endpoint.body, token: token, timeout: endpoint.timeout.seconds, accept: "application/json"
            )
            let (data, response) = try await transport(request, endpoint: endpoint.telemetryName)
            if (200..<300).contains(response.statusCode) { return (data, response) }
            // Only a 401 for the token this request carried may refresh and retry (once).
            if response.statusCode == 401, let token, !retried {
                retried = true
                if await tokens.unauthorized(token: token) { continue }
            }
            observer?.didFail(endpoint: endpoint.telemetryName, status: response.statusCode)
            throw ErrorMapping.map(response: response, body: data)
        }
    }

    private func transport(_ request: URLRequest, endpoint: String) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.network }
            return (data, http)
        } catch let error as APIError {
            observer?.didFail(endpoint: endpoint, status: 0)
            throw error
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw APIError.cancelled }
            observer?.didFail(endpoint: endpoint, status: 0)
            throw APIError.network
        }
    }
}
