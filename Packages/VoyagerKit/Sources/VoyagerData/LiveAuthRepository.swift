import Foundation
import Networking
import VoyagerModel

import AuthCore

/// `AuthAPI` over `APIClient`. `providers()` maps a 404 to `[]` (the catalogue then treats all four as unconfigured).
public struct LiveAuthAPI: AuthAPI {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func login(username: String, password: String) async throws -> LoginResponse {
        try await api.send(Endpoints.login(username: username, password: password))
    }
    public func changePassword(current: String, new: String) async throws -> String {
        try await api.send(Endpoints.changePassword(current: current, new: new)).accessToken
    }
    public func me() async throws -> User { try await api.send(Endpoints.me()) }

    public func providers() async throws -> [AuthProviderInfo] {
        do {
            let (value, _) = try await api.raw(Endpoints.providers())
            return try AuthProviderInfo.decodeList(from: try value.jsonData())
        } catch APIError.notFound {
            return []
        } catch is DecodingError {
            throw APIError.decoding
        }
    }
}
