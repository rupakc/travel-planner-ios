import Foundation
import Networking
import os
import Testing
import VoyagerModel

final class FakeTokens: AccessTokenProvider, Sendable {
    private let token: String?
    init(token: String?) { self.token = token }
    func currentToken() async -> String? { token }
    func unauthorized(token: String) async -> Bool { false }
}

/// Env + clients over a `StubServer` (unique host per test, so tests run in parallel).
struct Harness {
    let stub: StubServer
    let api: APIClient
    let sse: SSEClient
    let language: OSAllocatedUnfairLock<AppLanguage>

    init(token: String? = "tok", language: AppLanguage = .de, _ handler: @escaping StubServer.Handler = { _ in .init() }) throws {
        stub = StubServer(handler)
        let env = ServerEnvironment(
            buildBaseURL: stub.baseURL, trustedHosts: [], allowsOverride: false,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let tokens = FakeTokens(token: token)
        api = APIClient(server: env, tokens: tokens, session: stub.session())
        sse = SSEClient(server: env, tokens: tokens, configuration: stub.configuration())
        self.language = OSAllocatedUnfairLock(initialState: language)
    }

    var locale: @Sendable () -> AppLanguage { let box = language; return { box.withLock { $0 } } }

    func body(_ index: Int = 0) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(stub.bodies[safe: index]))
    }
    var request: URLRequest? { stub.requests.first }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
