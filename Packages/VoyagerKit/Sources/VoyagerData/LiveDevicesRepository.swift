import Foundation
import Networking
import VoyagerModel

public struct LiveDevicesRepository: DevicesRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func register(_ registration: DeviceRegistration) async throws -> Device {
        try await api.send(Endpoints.registerDevice(registration))
    }
    /// Unwraps `{"items": [...]}`.
    public func list() async throws -> [Device] { try await api.send(Endpoints.devices()).items }
    public func delete(id: Int) async throws { _ = try await api.send(Endpoints.deleteDevice(id: id)) }
    public func unregister(token: String) async throws { _ = try await api.send(Endpoints.unregisterDevice(token: token)) }
}
