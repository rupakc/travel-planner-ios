import Domain
import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// One destination column of the comparison: its request and how loading it went.
public struct CompareColumn: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case loading
        case done(CompareSummary)
        case failed(String)
    }

    public var destination: String
    public var request: TravelSearchRequest
    public var status: Status

    public var summary: CompareSummary? {
        if case .done(let summary) = status { return summary }
        return nil
    }

    public var isLoading: Bool { status == .loading }
    public var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }
}

/// State of the Compare mode: the shared trip fields, 2-3 destinations and one column per destination.
@MainActor @Observable
public final class CompareModel {
    public static let maxDestinations = 3
    public static let interestIDs = [
        "food", "history", "adventure", "culture", "nature", "shopping", "nightlife", "wellness", "art", "family",
    ]

    public var origin = ""
    public var destinations = ["", ""]
    public var nationality = ""
    public var departure: Date
    public var returnDate: Date
    public var budget = ""
    public var adults = 1
    public var interests: Set<String> = []
    public private(set) var columns: [CompareColumn] = []
    public private(set) var needTwo = false

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var prefilled = false

    public init(env: AppEnvironment, now: Date = Date(), track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
        let calendar = Calendar(identifier: .gregorian)
        departure = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        returnDate = calendar.date(byAdding: .day, value: 14, to: now) ?? now
    }

    public var isLoading: Bool { columns.contains { $0.isLoading } }
    public var canAddDestination: Bool { destinations.count < Self.maxDestinations }
    public var canRemoveDestination: Bool { destinations.count > 2 }

    /// The best column indexes per row, over the finished columns only.
    public var best: [String: Set<Int>] {
        CompareRules.bestByRow(columns.map { $0.summary.map(Self.json) ?? .null })
    }

    public func addDestination() {
        if canAddDestination { destinations.append("") }
    }

    public func removeDestination(at index: Int) {
        guard canRemoveDestination, destinations.indices.contains(index) else { return }
        destinations.remove(at: index)
    }

    public func toggle(_ interest: String) {
        if interests.contains(interest) { interests.remove(interest) } else { interests.insert(interest) }
    }

    /// Seeds nationality, interests and travellers from the saved preferences once (a failure leaves the form blank).
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

    /// The shared fields as the web's compare form (snake_case keys), input of `CompareRules.requests`.
    func form() -> JSONValue {
        .object([
            "origin": .string(origin.trimmingCharacters(in: .whitespacesAndNewlines)),
            "destinations": .array(destinations.map(JSONValue.string)),
            "departure_date": .string(Self.apiDate(departure)),
            "return_date": .string(Self.apiDate(returnDate)),
            "nationality": .string(nationality.trimmingCharacters(in: .whitespacesAndNewlines)),
            "interests": .array(Self.interestIDs.filter { interests.contains($0) }.map(JSONValue.string)),
            "budget_usd": .string(budget.trimmingCharacters(in: .whitespacesAndNewlines)),
            "adults": .number(Double(adults)),
        ])
    }

    /// Builds one request per distinct destination and loads every column in parallel.
    /// Fewer than two destinations only sets `needTwo`.
    public func compare() async {
        guard !isLoading else { return }
        let requests = Self.decode(CompareRules.requests(form: form()))
        guard requests.count >= 2 else {
            needTwo = true
            return
        }
        needTwo = false
        run += 1
        let token = run
        columns = requests.map { CompareColumn(destination: $0.destination ?? "", request: $0, status: .loading) }
        await loadAll(indexes: Array(columns.indices), token: token)
    }

    /// Retries one failed column; the other columns are not touched.
    public func retry(_ index: Int) async {
        guard columns.indices.contains(index), columns[index].isFailed else { return }
        columns[index].status = .loading
        await loadAll(indexes: [index], token: run)
    }

    private func loadAll(indexes: [Int], token: Int) async {
        let repo = env.repos.compare
        let work = indexes.map { ($0, columns[$0].request) }
        await withTaskGroup(of: (Int, Result<CompareSummary, any Error>).self) { group in
            for (index, request) in work {
                group.addTask {
                    do { return (index, .success(try await repo.summary(request))) } catch { return (index, .failure(error)) }
                }
            }
            for await (index, result) in group {
                // A newer run replaced the columns: drop this answer.
                guard token == run, columns.indices.contains(index) else { continue }
                switch result {
                case .success(let summary): columns[index].status = .done(summary)
                case .failure(let error): columns[index].status = .failed(Self.reason(for: error))
                }
            }
        }
    }

    /// "Plan this trip": tracks `search_submit(mode: compare)` and opens Results for the compared request.
    public func plan(_ index: Int) {
        guard columns.indices.contains(index), columns[index].summary != nil else { return }
        let request = columns[index].request
        let nights = max(1, Calendar(identifier: .gregorian).dateComponents([.day], from: departure, to: returnDate).day ?? 1)
        track(.searchSubmit(mode: .compare, travelers: request.numTravelers ?? adults, nights: nights, multiCity: false))
        env.router.open(.results(request))
    }

    /// The backend's own text when it sent one, else the web's "check the trip details" (4xx) or "unavailable".
    static func reason(for error: any Error) -> String {
        if let api = error as? APIError {
            if let detail = api.userFacingDetail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty { return detail }
            if case .client = api { return L10n.text(K.misc.compare.errorCheck) }
            if case .forbidden = api { return L10n.text(K.misc.compare.errorCheck) }
            if case .notFound = api { return L10n.text(K.misc.compare.errorCheck) }
        }
        return L10n.text(K.misc.compare.errorUnavailable)
    }

    static func decode(_ values: [JSONValue]) -> [TravelSearchRequest] {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        return values.compactMap { value in
            guard let data = try? encoder.encode(value) else { return nil }
            return try? decoder.decode(TravelSearchRequest.self, from: data)
        }
    }

    /// A summary in the backend's JSON shape, for `CompareRules.bestByRow`.
    static func json(_ summary: CompareSummary) -> JSONValue {
        guard let data = try? JSONEncoder().encode(summary),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .null }
        return value
    }

    static func apiDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Shows `columns` without a request (snapshot tests).
    func show(_ columns: [CompareColumn]) { self.columns = columns }
}
