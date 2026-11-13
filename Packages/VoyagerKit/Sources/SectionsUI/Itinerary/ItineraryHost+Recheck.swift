import Foundation
import VoyagerModel

extension ItineraryHost {
    /// The stress-test call for hosts that keep the itinerary in My Plan selections (Plan, Chat, Results): sends
    /// the edited itinerary with the plan's search to `repos.agents.stressTest`. A failure becomes
    /// `ItineraryRecheckError` carrying `message(error)` (the server's own text, such as a 429 detail; never
    /// exception text). Nil without a usable search (the view then hides Re-check).
    @MainActor
    public static func recheck(
        agents: any AgentsRepository,
        searchData: JSONValue?,
        message: @escaping @Sendable (any Error) -> String?
    ) -> (@MainActor @Sendable (JSONValue) async throws -> JSONValue)? {
        guard let searchData, searchData.object != nil, let body = try? JSONEncoder().encode(searchData),
            let request = try? JSONDecoder().decode(TravelSearchRequest.self, from: body)
        else { return nil }
        return { itinerary in
            do {
                return try await agents.stressTest(itinerary: itinerary, request: request)
            } catch {
                throw ItineraryRecheckError(message: message(error))
            }
        }
    }
}
