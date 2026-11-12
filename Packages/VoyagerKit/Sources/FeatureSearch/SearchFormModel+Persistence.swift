import Foundation
import VoyagerModel

extension SearchFormModel {
    /// A request from elsewhere (Discover, Compare, Results "edit") fills the form.
    func apply(_ request: TravelSearchRequest) {
        keepsOwnValues = true
        applyJourney(request)
        origin.set(external: request.origin ?? "")
        nationality.set(external: request.nationality ?? "")
        applyDates(departure: request.departureDate, return: request.returnDate)
        permits = request.residencePermits ?? []
        visas = request.existingVisas ?? []
        interests = request.interests ?? []
        accessibility = request.accessibilityNeeds ?? []
        if let budget = request.budgetUsd { budgetText = Self.budgetString(budget) }
        setParty(
            adults: request.adults ?? max(1, request.numTravelers ?? 1), seniors: request.seniors ?? 0,
            children: request.children ?? 0, infants: request.infants ?? 0)
        pace = request.pace ?? pace
        serendipity = request.serendipity ?? serendipity
    }

    /// `destinations` is the journey with the final destination last: everything before it is a stop.
    private func applyJourney(_ request: TravelSearchRequest) {
        let journey = request.destinations ?? []
        guard journey.count > 1 else {
            destination.set(external: request.destination ?? "")
            return
        }
        let nights = request.destinationNights ?? []
        stops = journey.dropLast().enumerated().map { index, city in
            var stop = StopDraft(place: makeAirportField(city))
            stop.nights = (index < nights.count ? nights[index] : nil).map(String.init) ?? ""
            return stop
        }
        destination.set(external: request.destination ?? journey.last ?? "")
    }

    private func applyDates(departure start: String?, return end: String?) {
        if let start = Self.date(start) { departure = start }
        if let end = Self.date(end) {
            returnDate = end
            hasReturn = true
        } else if start != nil {
            hasReturn = false
        }
    }

    func setParty(adults: Int, seniors: Int, children: Int, infants: Int) {
        guard adults + seniors + children + infants >= 1 else { return }
        self.adults = adults
        self.seniors = seniors
        self.children = children
        self.infants = infants
    }

    /// Loads a recent search into the form. Past dates move a week out from today, keeping the trip length.
    public func fill(from recent: RecentSearch) {
        keepsOwnValues = true
        let search = recent.search
        origin.set(external: search["origin"].string ?? "")
        destination.set(external: search["destination"].string ?? "")
        nationality.set(external: search["nationality"].string ?? "")
        stops = (search["stops"].array ?? []).compactMap(stopDraft)
        permits = strings(search["residence_permits"])
        visas = strings(search["existing_visas"])
        interests = strings(search["interests"])
        accessibility = strings(search["accessibility_needs"])
        budgetText = search["budget_usd"].double.map(Self.budgetString) ?? ""
        setParty(
            adults: search["adults"].int ?? 1, seniors: search["seniors"].int ?? 0,
            children: search["children"].int ?? 0, infants: search["infants"].int ?? 0)
        serendipity = search["serendipity"].double ?? 0.5
        let shifted = fillDates(departure: search["departure_date"].string, return: search["return_date"].string)
        notice = RecentNotice(route: "\(Self.short(origin.value)) → \(Self.short(destination.value))", datesShifted: shifted)
    }

    private func stopDraft(_ item: JSONValue) -> StopDraft? {
        guard let city = item["city"].string, !city.isEmpty else { return nil }
        var stop = StopDraft(place: makeAirportField(city))
        stop.nights = item["nights"].int.map(String.init) ?? ""
        return stop
    }

    /// Sets the dates of a recent search; true when they had passed and moved a week out.
    private func fillDates(departure startText: String?, return endText: String?) -> Bool {
        var start = Self.date(startText) ?? departure
        var end = Self.date(endText)
        let shifted = start < today
        if shifted {
            let length = end.map { Self.calendar.dateComponents([.day], from: start, to: $0).day ?? 0 }
            start = Self.calendar.date(byAdding: .day, value: 7, to: today) ?? today
            end = length.flatMap { Self.calendar.date(byAdding: .day, value: $0, to: start) }
        }
        departure = start
        hasReturn = end != nil
        returnDate = end ?? returnDate
        return shifted
    }

    public func dismissNotice() { notice = nil }

    /// Removes a recent search at once; it comes back if the server refuses.
    @discardableResult
    public func deleteRecent(_ recent: RecentSearch) -> Task<Void, Never> {
        let before = recents
        recents.removeAll { $0.id == recent.id }
        return Task { [repos = env.repos] in
            do {
                try await repos.recent.delete(id: recent.id)
            } catch {
                self.recents = before
            }
        }
    }

    static func short(_ place: String) -> String {
        place.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? place
    }

    private func strings(_ value: JSONValue) -> [String] { (value.array ?? []).compactMap(\.string) }

    private static func budgetString(_ amount: Double) -> String {
        amount == amount.rounded() ? String(Int(amount)) : String(amount)
    }

    /// The `POST /api/recent-searches` body: the form as submitted (same shape as the web's).
    func recentPayload(_ request: TravelSearchRequest) -> JSONValue {
        let journey = filledStops
        return .object([
            "origin": .string(request.origin ?? ""),
            "destination": .string(request.destination ?? ""),
            "departure_date": .string(request.departureDate ?? ""),
            "return_date": request.returnDate.map { JSONValue.string($0) } ?? .null,
            "stops": .array(journey.map { stop in
                JSONValue.object(["city": .string(stop.city), "nights": Self.number(stop.nights)])
            }),
            "nationality": .string(request.nationality ?? ""),
            "residence_permits": .array((request.residencePermits ?? []).map(JSONValue.string)),
            "existing_visas": .array((request.existingVisas ?? []).map(JSONValue.string)),
            "interests": .array((request.interests ?? []).map(JSONValue.string)),
            "budget_usd": request.budgetUsd.map { JSONValue.number($0) } ?? .null,
            "adults": .number(Double(adults)),
            "children": .number(Double(children)),
            "seniors": .number(Double(seniors)),
            "infants": .number(Double(infants)),
            "accessibility_needs": .array((request.accessibilityNeeds ?? []).map(JSONValue.string)),
            "serendipity": .number(serendipity),
        ])
    }

    private static func number(_ value: Int?) -> JSONValue { value.map { JSONValue.number(Double($0)) } ?? .null }

    struct PreferenceFields: Sendable {
        var nationality: String
        var permits: [String]
        var visas: [String]
        var interests: [String]
        var adults: Int
        var children: Int
        var seniors: Int
        var infants: Int
        var accessibility: [String]
        var budget: Double?
    }

    /// The server's preferences with the form's values on top; fields the form leaves alone are kept.
    static func merged(_ current: Preferences, with fields: PreferenceFields) -> Preferences {
        var result = current
        if !fields.nationality.isEmpty { result.nationality = fields.nationality }
        if (current.residencePermits ?? []) != fields.permits { result.residencePermits = fields.permits }
        if (current.existingVisas ?? []) != fields.visas { result.existingVisas = fields.visas }
        if (current.interests ?? []) != fields.interests { result.interests = fields.interests }
        if (current.accessibilityNeeds ?? []) != fields.accessibility { result.accessibilityNeeds = fields.accessibility }
        mergeParty(&result, current: current, fields: fields)
        if let budget = fields.budget { result.budgetCategory = budget <= 1500 ? "low" : budget <= 5000 ? "medium" : "high" }
        return result
    }

    private static func mergeParty(_ result: inout Preferences, current: Preferences, fields: PreferenceFields) {
        let same = (current.adults ?? 1) == fields.adults && (current.children ?? 0) == fields.children
            && (current.seniors ?? 0) == fields.seniors && (current.infants ?? 0) == fields.infants
        guard !same else { return }
        result.adults = fields.adults
        result.children = fields.children
        result.seniors = fields.seniors
        result.infants = fields.infants
        result.numTravelers = fields.adults + fields.children + fields.seniors + fields.infants
    }
}
