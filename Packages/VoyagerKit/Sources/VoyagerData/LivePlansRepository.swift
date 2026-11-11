import Foundation
import Networking
import VoyagerModel

public struct LivePlansRepository: PlansRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func list() async throws -> [PlanSummary] { try await api.send(Endpoints.plans()) }
    public func get(id: Int) async throws -> SavedPlan { try await api.send(Endpoints.plan(id: id)) }
    public func create(_ plan: NewPlan) async throws -> SavedPlan { try await api.send(Endpoints.createPlan(plan)) }
    public func update(id: Int, _ update: PlanUpdate) async throws -> SavedPlan {
        try await api.send(Endpoints.updatePlan(id: id, update))
    }
    public func delete(id: Int) async throws { _ = try await api.send(Endpoints.deletePlan(id: id)) }
    public func share(id: Int) async throws -> String { try await api.send(Endpoints.sharePlan(id: id)).shareToken }
    public func shared(token: String) async throws -> SharedPlan { try await api.send(Endpoints.sharedPlan(token: token)) }
}
