import Domain
import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// Translates the web-style `"ns:path"` keys the Domain plan helpers emit through the String Catalog.
enum PlanTranslator {
    static let text: PlanText = { key, params in
        L10n.text(LKey(key, placeholders: Set(params.keys), plural: false), params)
    }

    static var locale: Locale { LanguageController.current.intlLocale }
}

/// The hotels the "Find cheaper hotels" call returned.
enum CheaperHotels: Equatable {
    case loading
    case loaded(maxNightly: Double, hotels: [JSONValue])
    case failed(String)
}

/// A remix whose "before" numbers the next Results screen compares against.
struct RemixBaseline: Equatable {
    let presetID: String
    let before: JSONValue
}

/// Remix opens a new Results screen (a fresh model), so the numbers to compare against wait here, keyed by the
/// search data that screen will carry.
@MainActor
enum RemixBaselines {
    private static var store: [JSONValue: RemixBaseline] = [:]
    static func set(_ baseline: RemixBaseline, for searchData: JSONValue) { store[searchData] = baseline }
    static func baseline(for searchData: JSONValue?) -> RemixBaseline? { searchData.flatMap { store[$0] } }
    static func clear(for searchData: JSONValue?) { if let searchData { store[searchData] = nil } }
    static func removeAll() { store.removeAll() }
}

/// State and actions of the plan tools (best value, budget planner, remix). Client-side except "Find cheaper
/// hotels", which calls the existing hotel filter.
@MainActor @Observable
final class PlanToolsModel {
    var budgetEdit: BudgetPlanner.Allocation?
    var undoSelections: JSONValue?
    var toast: ToastMessage?
    var cheaper: CheaperHotels?
    var baselineDismissed = false

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var cheaperTask: Task<Void, Never>?

    init(env: AppEnvironment, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
    }

    private func used(_ feature: String) { track(.featureUsed(feature: feature, page: "results")) }

    // MARK: - Budget planner

    func allocation(searchData: JSONValue?, results: JSONValue) -> BudgetPlanner.Allocation? {
        budgetEdit ?? BudgetPlanner.defaultAllocation(searchData, results)
    }

    func fit(searchData: JSONValue?, results: JSONValue) -> (BudgetPlanner.Allocation, BudgetPlanner.FitResult)? {
        guard let allocation = allocation(searchData: searchData, results: results) else { return nil }
        return (allocation, BudgetPlanner.fitResults(results, allocation, searchData))
    }

    func change(_ key: String, to value: Double, searchData: JSONValue?, results: JSONValue) {
        guard let base = allocation(searchData: searchData, results: results) else { return }
        budgetEdit = BudgetPlanner.reallocate(base, key: key, value: .number(value), total: base.sum)
        used("budget_planner")
    }

    func setTotal(_ total: Double, searchData: JSONValue?, results: JSONValue) {
        guard total.isFinite, total > 0, let base = allocation(searchData: searchData, results: results) else { return }
        budgetEdit = BudgetPlanner.withTotal(base, total: .number(total))
        used("budget_planner")
    }

    func resetBudget() { budgetEdit = nil }

    /// The most a hotel night may cost to fit the stay share (nil: nothing to offer).
    static func maxNightly(_ allocation: BudgetPlanner.Allocation, _ fit: BudgetPlanner.FitResult) -> Double? {
        guard fit.nights > 0, fit.hotels.count < 3 else { return nil }
        let nightly = (allocation.stay / fit.nights).rounded(.down)
        return nightly.isFinite && nightly >= 1 ? nightly : nil
    }

    /// The only API call of the tools: the hotel filter with a nightly cap.
    func findCheaperHotels(maxNightly: Double, searchData: JSONValue?) {
        guard cheaper != .loading, let request = Self.request(from: searchData) else { return }
        used("budget_planner")
        cheaper = .loading
        cheaperTask = Task { [weak self, agents = env.repos.agents] in
            let outcome: CheaperHotels
            do {
                let data = try await agents.filtered(
                    .hotels, request: request, filters: ["max_price_per_night_usd": .number(maxNightly)])
                if let message = data["error"].string {
                    outcome = .failed(message)
                } else {
                    let hotels = data["results"].array ?? data.array ?? []
                    outcome = .loaded(maxNightly: maxNightly, hotels: hotels)
                }
            } catch is CancellationError {
                return
            } catch {
                outcome = .failed((error as? any ErrorPresentable)?.userFacingDetail ?? L10n.text(K.sections.page.filterError))
            }
            self?.cheaper = outcome
        }
    }

    func cancel() { cheaperTask?.cancel() }

    // MARK: - Best value

    func package(results: JSONValue, searchData: JSONValue?, fit: BudgetPlanner.FitResult?) -> JSONValue? {
        let caps = budgetEdit != nil ? fit.map(BudgetPlanner.capsFromFit) : nil
        return BestValuePackage.build(
            results: results, searchData: searchData ?? .object([:]), caps: caps,
            translate: PlanTranslator.text, locale: PlanTranslator.locale)
    }

    func applyPackage(_ pkg: JSONValue) {
        undoSelections = env.plan.selections
        env.plan.selections = BestValuePackage.apply(env.plan.selections, pkg)
        used("best_value")
        toast = ToastMessage(L10n.text(K.plan.best.added))
    }

    func undoPackage() {
        guard let previous = undoSelections else { return }
        env.plan.selections = previous
        undoSelections = nil
    }

    // MARK: - Remix

    /// Re-runs the search with the preset applied (a new Results screen). False when the preset changes nothing.
    @discardableResult
    func remix(_ preset: RemixPreset, searchData: JSONValue?, results: JSONValue) -> Bool {
        guard let searchData else { return false }
        let remixed = Remix.apply(searchData, presetID: preset.id)
        guard remixed != searchData, let request = Self.request(from: remixed) else { return false }
        used("remix")
        RemixBaselines.set(
            RemixBaseline(presetID: preset.id, before: Remix.snapshotMetrics(results)),
            for: ResultsModel.searchData(for: request))
        env.plan.selections = Selections.empty // a re-run resets the selections, like the web
        env.router.open(.results(request))
        return true
    }

    static func isApplicable(_ preset: RemixPreset, searchData: JSONValue?) -> Bool {
        guard let searchData else { return false }
        return Remix.apply(searchData, presetID: preset.id) != searchData
    }

    static func request(from searchData: JSONValue?) -> TravelSearchRequest? {
        guard let searchData, let data = try? JSONEncoder().encode(searchData) else { return nil }
        return try? JSONDecoder().decode(TravelSearchRequest.self, from: data)
    }
}
