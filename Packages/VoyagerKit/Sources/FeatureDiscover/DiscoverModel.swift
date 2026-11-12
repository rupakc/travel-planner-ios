import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// State of the "Surprise me" form and its five suggestion cards.
@MainActor @Observable
public final class DiscoverModel {
    public enum Phase: Equatable {
        case idle
        case loading
        case loaded([DiscoverSuggestion])
        case failed(String)
    }

    /// The web's interest chips, in order (ids are the values sent to the backend).
    public static let interestIDs = [
        "food", "history", "adventure", "culture", "nature", "shopping", "nightlife", "wellness", "art", "family",
    ]

    public var origin = ""
    public var nationality = ""
    public var departure: Date
    public var returnDate: Date
    public var budget = ""
    public var adults = 1
    public var interests: Set<String> = []
    public private(set) var phase: Phase = .idle

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var prefilled = false

    /// `track` defaults to the environment's telemetry; `now` fixes the date defaults (departure +7 d, return +14 d).
    public init(env: AppEnvironment, now: Date = Date(), track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
        let calendar = Calendar(identifier: .gregorian)
        departure = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        returnDate = calendar.date(byAdding: .day, value: 14, to: now) ?? now
    }

    public var isBusy: Bool { phase == .loading }

    /// Same rule as the web button: origin and nationality are required.
    public var canSubmit: Bool {
        !isBusy && !origin.trimmed.isEmpty && !nationality.trimmed.isEmpty
    }

    public var suggestions: [DiscoverSuggestion] {
        if case .loaded(let list) = phase { return list }
        return []
    }

    /// Fills nationality, interests and travellers from the saved preferences once (a failure just leaves the form blank).
    public func prefillFromPreferences() async {
        guard !prefilled else { return }
        prefilled = true
        guard let prefs = try? await env.repos.preferences.get() else { return }
        if nationality.isEmpty, let value = prefs.nationality { nationality = value }
        if origin.isEmpty, let value = prefs.currentResidence { origin = value }
        if interests.isEmpty, let value = prefs.interests {
            interests = Set(value.filter { Self.interestIDs.contains($0) })
        }
        if let count = prefs.adults, count > 0 { adults = count }
    }

    /// Shows `list` without a request (snapshot tests).
    func show(_ list: [DiscoverSuggestion]) { phase = .loaded(list) }

    public func toggle(_ interest: String) {
        if interests.contains(interest) { interests.remove(interest) } else { interests.insert(interest) }
    }

    public func request() -> DiscoverRequest {
        DiscoverRequest(
            origin: origin.trimmed,
            nationality: nationality.trimmed,
            departureDate: Self.apiDate(departure),
            returnDate: Self.apiDate(returnDate),
            budgetUsd: Double(budget.trimmed),
            interests: Self.interestIDs.filter { interests.contains($0) },
            adults: adults)
    }

    public func find() async {
        guard canSubmit else { return }
        phase = .loading
        do {
            let list = try await env.repos.discover.suggestions(request())
            phase = .loaded(list)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// "Plan this trip": tracks `search_submit(mode: discover)` and opens Results for that destination.
    public func planThis(_ suggestion: DiscoverSuggestion) {
        guard let city = suggestion.city?.trimmed, !city.isEmpty else { return }
        let destination = [city, suggestion.country?.trimmed].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let nights = max(1, Calendar(identifier: .gregorian).dateComponents([.day], from: departure, to: returnDate).day ?? 1)
        let search = TravelSearchRequest(
            origin: origin.trimmed,
            destination: destination,
            departureDate: Self.apiDate(departure),
            returnDate: Self.apiDate(returnDate),
            nationality: nationality.trimmed,
            interests: Self.interestIDs.filter { interests.contains($0) },
            budgetUsd: Double(budget.trimmed),
            numTravelers: adults,
            adults: adults)
        track(.searchSubmit(mode: .discover, travelers: adults, nights: nights, multiCity: false))
        env.router.open(.results(search))
    }

    /// A 429 or 503 (`ai_limit`) shows the backend's own text; other failures the same, else the web's "Discovery failed".
    static func message(for error: any Error) -> String {
        if let api = error as? APIError {
            if let detail = api.userFacingDetail?.trimmed, !detail.isEmpty { return detail }
            switch api.presentationKind {
            case .unauthorized, .rateLimited, .network:
                return ErrorCopy.message(kind: api.presentationKind, detail: nil)
            case .server, .other:
                break
            }
        }
        return L10n.text(K.search.discover.failed)
    }

    static func apiDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
