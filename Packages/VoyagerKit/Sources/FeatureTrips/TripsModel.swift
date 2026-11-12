import Domain
import Foundation
import Networking
import Observation
import VoyagerEnv
import VoyagerModel

/// Which saved plans the list shows.
enum PlanFilter: String, CaseIterable, Sendable {
    case all, upcoming, past
}

/// The offline copy of the plan list (`Application Support/plans-cache.json`). It records whose list it is, so
/// another account never reads it.
struct PlansCache: Codable, Sendable, Equatable {
    static let path = "plans-cache.json"
    var username: String?
    var plans: [PlanSummary]
}

/// The dates a plan's `search_data` holds (both optional: a plan may have none).
struct TripDates: Equatable, Sendable {
    var departure: Date?
    var returning: Date?

    init(_ plan: PlanSummary, calendar: Calendar = .current) {
        departure = Self.date(plan.searchData["departure_date"].string, calendar)
        returning = Self.date(plan.searchData["return_date"].string, calendar)
    }

    /// `yyyy-MM-dd` (a longer ISO string keeps its first ten characters) at the start of that day.
    static func date(_ text: String?, _ calendar: Calendar) -> Date? {
        guard let text, text.count >= 10 else { return nil }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The last day of the trip: the return date, else the departure.
    var end: Date? { returning ?? departure }
}

/// The Trips tab: the saved plans (cached for offline reading), the next trip, search and filter, delete.
@MainActor @Observable
final class TripsModel {
    private(set) var plans: [PlanSummary] = []
    private(set) var isLoading = false
    /// The refresh failed and the list is the cached copy.
    private(set) var isOffline = false
    /// The refresh failed with nothing cached to show.
    private(set) var failed = false
    private(set) var error: (any ErrorPresentable)?
    /// A delete failed.
    private(set) var deleteFailed = false
    var query = ""
    var filter: PlanFilter = .all
    /// The plan the user asked to delete; the confirmation dialog shows while it is set.
    var pendingDelete: PlanSummary?

    private let env: AppEnvironment
    private let files: any FileStore
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        env: AppEnvironment,
        files: (any FileStore)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.env = env
        self.files = files ?? DiskFileStore.applicationSupport()
        self.now = now
        self.calendar = calendar
    }

    private var username: String? { env.auth.session?.user.username }

    // MARK: - Loading

    /// Shows the cached list at once, then refreshes it. A failed refresh keeps the cache and sets `isOffline`.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if plans.isEmpty, let cached = await readCache() { plans = cached }
        do {
            let fresh = try await env.repos.plans.list()
            plans = fresh
            isOffline = false
            failed = false
            error = nil
            await writeCache(fresh)
        } catch is CancellationError {
            return
        } catch APIError.cancelled {
            return
        } catch {
            if plans.isEmpty {
                failed = true
                self.error = error as? any ErrorPresentable
            } else {
                isOffline = true
            }
        }
    }

    private func readCache() async -> [PlanSummary]? {
        guard let data = try? await files.read(PlansCache.path),
            let cache = try? JSONDecoder().decode(PlansCache.self, from: data), cache.username == username
        else { return nil }
        return cache.plans
    }

    private func writeCache(_ plans: [PlanSummary]) async {
        guard let data = try? JSONEncoder().encode(PlansCache(username: username, plans: plans)) else { return }
        try? await files.write(data, to: PlansCache.path)
    }

    // MARK: - Derived lists

    private var today: Date { calendar.startOfDay(for: now()) }

    /// The plan with the nearest departure that is today or later.
    var upcoming: PlanSummary? { Self.upcoming(in: plans, now: now(), calendar: calendar) }

    static func upcoming(in plans: [PlanSummary], now: Date, calendar: Calendar = .current) -> PlanSummary? {
        let today = calendar.startOfDay(for: now)
        let dated: [(plan: PlanSummary, departure: Date)] = plans.compactMap { plan in
            guard let departure = TripDates(plan, calendar: calendar).departure, departure >= today else { return nil }
            return (plan, departure)
        }
        return dated.min { $0.departure < $1.departure }?.plan
    }

    /// A trip is past once its last day is before today; a plan without dates is neither upcoming nor past.
    func isPast(_ plan: PlanSummary) -> Bool {
        guard let end = TripDates(plan, calendar: calendar).end else { return false }
        return end < today
    }

    func isUpcoming(_ plan: PlanSummary) -> Bool {
        guard let end = TripDates(plan, calendar: calendar).end else { return false }
        return end >= today
    }

    /// The list after the search text and the filter.
    var visiblePlans: [PlanSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return plans.filter { plan in
            switch filter {
            case .all: break
            case .upcoming: guard isUpcoming(plan) else { return false }
            case .past: guard isPast(plan) else { return false }
            }
            guard !needle.isEmpty else { return true }
            let haystack = [plan.name, plan.searchData["destination"].string, plan.searchData["origin"].string]
            return haystack.contains { $0?.localizedCaseInsensitiveContains(needle) == true }
        }
    }

    func departure(of plan: PlanSummary) -> Date? { TripDates(plan, calendar: calendar).departure }

    // MARK: - Delete

    func requestDelete(_ plan: PlanSummary) { pendingDelete = plan }

    func cancelDelete() { pendingDelete = nil }

    /// Deletes the plan the user confirmed. It leaves the list only once the server has deleted it.
    @discardableResult
    func confirmDelete() async -> Bool {
        guard let plan = pendingDelete else { return false }
        pendingDelete = nil
        do {
            try await env.repos.plans.delete(id: plan.id)
        } catch {
            deleteFailed = true
            return false
        }
        deleteFailed = false
        await didDelete(id: plan.id)
        return true
    }

    /// The server no longer has plan `id` (deleted here or from the detail screen): drop it from the list and the cache.
    func didDelete(id: Int) async {
        plans.removeAll { $0.id == id }
        if env.plan.savedPlanID == id { env.plan.savedPlanID = nil }
        await writeCache(plans)
    }

    func clearDeleteFailure() { deleteFailed = false }
}
