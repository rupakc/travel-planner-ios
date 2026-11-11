import Foundation
import Networking
import VoyagerModel

public struct LivePreferencesRepository: PreferencesRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func get() async throws -> Preferences { try await api.send(Endpoints.preferences()) }
    public func put(_ preferences: Preferences) async throws -> Preferences {
        try await api.send(Endpoints.putPreferences(preferences))
    }
    public func taste() async throws -> TasteProfile { try await api.send(Endpoints.tasteProfile()) }
    public func resetTaste() async throws { _ = try await api.send(Endpoints.resetTasteProfile()) }
    public func setEmail(_ email: String) async throws -> String? { try await api.send(Endpoints.setEmail(email)).email }
}
