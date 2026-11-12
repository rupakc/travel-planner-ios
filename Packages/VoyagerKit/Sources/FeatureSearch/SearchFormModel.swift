import Domain
import Foundation
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

public enum TravellerGroup: String, CaseIterable, Sendable {
    case adults, seniors, children, infants
}

/// Why the form cannot be submitted yet.
public enum SearchFormIssue: Equatable, Sendable {
    case missingRequired
    case returnBeforeDeparture
}

/// One stop on the way to the destination.
public struct StopDraft: Identifiable {
    public let id = UUID()
    public let place: Typeahead<AirportSuggestion>
    public var nights = ""
}

/// The message shown after a recent search was loaded into the form.
public struct RecentNotice: Equatable, Sendable {
    public let route: String
    public let datesShifted: Bool
}

/// The state and logic of the Search form (known-destination mode), UI-free so it is unit-tested directly.
@MainActor @Observable
public final class SearchFormModel {
    public static let maxStops = 3
    public static let maxTravellers = 20
    public static let recentLimit = 8
    public static let interestIDs = [
        "adventure", "art", "culture", "family", "food", "history", "nature", "nightlife", "shopping", "wellness",
    ]
    public static let accessibilityIDs = ["wheelchair", "visual_impairment", "hearing_impairment", "cognitive_disability"]
    public static let paceIDs = ["relaxed", "balanced", "packed"]
    /// The web's budget categories as dollars, and back.
    private static let budgetForCategory = ["low": 1000.0, "medium": 3000.0, "high": 8000.0]

    public let origin: Typeahead<AirportSuggestion>
    public let destination: Typeahead<AirportSuggestion>
    public let nationality: Typeahead<NationalitySuggestion>
    public internal(set) var stops: [StopDraft] = []
    public var departure: Date
    public var returnDate: Date
    public var hasReturn = true
    public var permits: [String] = []
    public var visas: [String] = []
    public internal(set) var interests: [String] = []
    public var budgetText = ""
    public internal(set) var adults = 1
    public internal(set) var children = 0
    public internal(set) var seniors = 0
    public internal(set) var infants = 0
    public internal(set) var accessibility: [String] = []
    public var pace: String?
    public var serendipity = 0.5
    public internal(set) var recents: [RecentSearch] = []
    public internal(set) var notice: RecentNotice?
    /// Set by a submit attempt that was blocked, so the form shows what is missing.
    public internal(set) var showIssues = false

    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored let debounce: Duration
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored var loadedPreferences: Preferences?
    /// True once a recent search or a prefill set the form, so the saved preferences do not overwrite it.
    @ObservationIgnored var keepsOwnValues = false

    public init(
        env: AppEnvironment,
        prefill: TravelSearchRequest? = nil,
        now: @escaping @MainActor () -> Date = { Date() },
        debounce: Duration = .milliseconds(250),
        track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.now = now
        self.debounce = debounce
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
        let reference = env.repos.reference
        origin = Typeahead(debounce: debounce) { try await reference.airports($0, limit: 8) }
        destination = Typeahead(debounce: debounce) { try await reference.airports($0, limit: 8) }
        nationality = Typeahead(debounce: debounce) { try await reference.nationalities($0, limit: 8) }
        let today = Self.calendar.startOfDay(for: now())
        departure = Self.calendar.date(byAdding: .day, value: 7, to: today) ?? today
        returnDate = Self.calendar.date(byAdding: .day, value: 14, to: today) ?? today
        pace = TravellerQuiz.pace(env.device.quizAnswers)
        if let prefill { apply(prefill) }
    }

    // MARK: - Dates

    static var calendar: Calendar { Calendar(identifier: .gregorian) }

    static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
    static func date(_ iso: String?) -> Date? { iso.flatMap { isoFormatter.date(from: $0) } }

    /// The first day a trip can start.
    public var today: Date { Self.calendar.startOfDay(for: now()) }

    /// Whole nights between departure and return; 0 without a return date.
    public var nights: Int {
        guard hasReturn else { return 0 }
        let days = Self.calendar.dateComponents(
            [.day], from: Self.calendar.startOfDay(for: departure), to: Self.calendar.startOfDay(for: returnDate)).day ?? 0
        return max(0, days)
    }

    // MARK: - Validation

    public var issue: SearchFormIssue? {
        if origin.value.isEmpty || destination.value.isEmpty || nationality.value.isEmpty { return .missingRequired }
        if hasReturn, Self.calendar.startOfDay(for: returnDate) < Self.calendar.startOfDay(for: departure) {
            return .returnBeforeDeparture
        }
        return nil
    }

    public var canSubmit: Bool { issue == nil }

    /// The date problem is shown at once; a missing field only after a blocked submit.
    public var visibleIssue: SearchFormIssue? {
        guard let issue else { return nil }
        return issue == .returnBeforeDeparture || showIssues ? issue : nil
    }

    // MARK: - Travellers

    public func count(_ group: TravellerGroup) -> Int {
        switch group {
        case .adults: adults
        case .seniors: seniors
        case .children: children
        case .infants: infants
        }
    }

    public var totalTravellers: Int { adults + children + seniors + infants }

    public func canChange(_ group: TravellerGroup, by delta: Int) -> Bool {
        let next = count(group) + delta
        guard next >= 0 else { return false }
        let total = totalTravellers + delta
        return total >= 1 && total <= Self.maxTravellers
    }

    /// Adds or removes a traveller; the party stays between 1 and 20.
    public func change(_ group: TravellerGroup, by delta: Int) {
        guard canChange(group, by: delta) else { return }
        let next = count(group) + delta
        switch group {
        case .adults: adults = next
        case .seniors: seniors = next
        case .children: children = next
        case .infants: infants = next
        }
    }

    public func toggleAccessibility(_ id: String) { toggle(id, in: &accessibility) }
    public func toggleInterest(_ id: String) { toggle(id, in: &interests) }

    private func toggle(_ id: String, in list: inout [String]) {
        if let index = list.firstIndex(of: id) { list.remove(at: index) } else { list.append(id) }
    }

    // MARK: - Stops

    public var canAddStop: Bool { stops.count < Self.maxStops }

    public func addStop() {
        guard canAddStop else { return }
        stops.append(StopDraft(place: makeAirportField()))
    }

    public func removeStop(id: UUID) { stops.removeAll { $0.id == id } }

    public func setNights(_ text: String, forStop id: UUID) {
        guard let index = stops.firstIndex(where: { $0.id == id }) else { return }
        stops[index].nights = String(text.filter(\.isNumber).prefix(2))
    }

    /// The stops with a city, in order.
    var filledStops: [(city: String, nights: Int?)] {
        stops.compactMap { stop in
            let city = stop.place.value
            guard !city.isEmpty else { return nil }
            let parsed = Int(stop.nights)
            return (city, parsed.flatMap { $0 > 0 ? $0 : nil })
        }
    }

    func makeAirportField(_ text: String = "") -> Typeahead<AirportSuggestion> {
        let reference = env.repos.reference
        return Typeahead(text: text, debounce: debounce) { try await reference.airports($0, limit: 8) }
    }

    // MARK: - Suggestions

    public static func label(_ airport: AirportSuggestion) -> String {
        let place = [airport.city, airport.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let code = airport.iataCode ?? ""
        return [code, place.isEmpty ? (airport.name ?? "") : place].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// Picks an airport into a place field: the code is the value, the label is what the field shows.
    public func pick(_ airport: AirportSuggestion, into field: Typeahead<AirportSuggestion>) {
        let code = airport.iataCode ?? airport.city ?? airport.name ?? ""
        field.choose(text: Self.label(airport), value: code)
    }

    public func pick(_ item: NationalitySuggestion) {
        let name = item.nationality ?? item.country ?? ""
        nationality.choose(text: name, value: name)
    }

    // MARK: - Loading

    /// Loads the saved preferences (pre-fill) and the recent searches. Never fails visibly.
    public func load() async {
        guard env.auth.session != nil else {
            recents = []
            return
        }
        let loaded = try? await env.repos.preferences.get()
        let list = try? await env.repos.recent.list()
        if let loaded {
            loadedPreferences = loaded
            applyPreferences(loaded)
        }
        if let list { recents = Array(list.prefix(Self.recentLimit)) }
    }

    public func refreshRecents() async {
        guard env.auth.session != nil, let list = try? await env.repos.recent.list() else { return }
        recents = Array(list.prefix(Self.recentLimit))
    }

    /// Saved preferences pre-fill the form; what a recent search or a prefill set stays.
    func applyPreferences(_ prefs: Preferences) {
        if nationality.value.isEmpty, let name = prefs.nationality, !name.isEmpty { nationality.set(external: name) }
        if permits.isEmpty { permits = prefs.residencePermits ?? [] }
        if visas.isEmpty { visas = prefs.existingVisas ?? [] }
        if interests.isEmpty { interests = prefs.interests ?? [] }
        if accessibility.isEmpty { accessibility = prefs.accessibilityNeeds ?? [] }
        if !keepsOwnValues { applyBudgetAndParty(prefs) }
    }

    private func applyBudgetAndParty(_ prefs: Preferences) {
        if let category = prefs.budgetCategory, let dollars = Self.budgetForCategory[category], budgetText.isEmpty {
            budgetText = String(Int(dollars))
        }
        if [prefs.adults, prefs.children, prefs.seniors, prefs.infants].contains(where: { $0 != nil }) {
            setParty(
                adults: prefs.adults ?? 1, seniors: prefs.seniors ?? 0, children: prefs.children ?? 0, infants: prefs.infants ?? 0)
        }
    }

    // MARK: - Submit

    public var budget: Double? {
        let cleaned = budgetText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(cleaned), amount > 0 else { return nil }
        return amount
    }

    /// The request the form describes: the language of the app goes with it.
    public func makeRequest() -> TravelSearchRequest {
        let journey = filledStops
        return TravelSearchRequest(
            origin: origin.value,
            destination: destination.value,
            departureDate: Self.iso(departure),
            returnDate: hasReturn ? Self.iso(returnDate) : nil,
            nationality: nationality.value,
            interests: interests.isEmpty ? nil : interests,
            budgetUsd: budget,
            numTravelers: max(1, totalTravellers),
            adults: adults,
            children: children,
            seniors: seniors,
            infants: infants,
            accessibilityNeeds: accessibility.isEmpty ? nil : accessibility,
            residencePermits: permits.isEmpty ? nil : permits,
            existingVisas: visas.isEmpty ? nil : visas,
            destinations: journey.isEmpty ? nil : journey.map { $0.city } + [destination.value],
            destinationNights: journey.isEmpty ? nil : journey.map { $0.nights } + [nil],
            pace: pace,
            serendipity: serendipity,
            locale: env.language.language)
    }

    /// Validates, records telemetry, opens Results, and starts the fire-and-forget writes (the recent search and
    /// the preference write-back). Returns that work (tests await it), or nil when the form is not valid.
    @discardableResult
    public func submit() -> Task<Void, Never>? {
        guard canSubmit else {
            showIssues = true
            return nil
        }
        showIssues = false
        notice = nil
        let request = makeRequest()
        track(.searchSubmit(
            mode: .search, travelers: max(1, totalTravellers), nights: nights, multiCity: !filledStops.isEmpty))
        let payload = recentPayload(request)
        let signedIn = env.auth.session != nil
        let fields = PreferenceFields(
            nationality: nationality.value, permits: permits, visas: visas, interests: interests,
            adults: adults, children: children, seniors: seniors, infants: infants, accessibility: accessibility,
            budget: budget)
        let known = loadedPreferences
        env.router.open(.results(request))
        guard signedIn else { return nil }
        return Task { [repos = env.repos] in
            try? await repos.recent.record(payload)
            if let list = try? await repos.recent.list() { self.recents = Array(list.prefix(Self.recentLimit)) }
            let current: Preferences?
            if let known { current = known } else { current = try? await repos.preferences.get() }
            guard let current else { return }
            let updated = Self.merged(current, with: fields)
            guard updated != current else { return }
            if (try? await repos.preferences.put(updated)) != nil { self.loadedPreferences = updated }
        }
    }
}
