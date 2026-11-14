import Foundation
import Networking
import Observation
import SectionsUI
import VoyagerEnv
import VoyagerModel

/// One read-only block of the plan: a section title and the items picked in it.
struct PlanBlock: Identifiable, Equatable {
    let section: SectionID
    let items: [SectionItem]
    var id: String { section.rawValue }
}

/// A saved plan on screen: read-only blocks, and the four actions (open in My Plan, share, export, delete).
@MainActor @Observable
final class PlanDetailModel {
    enum Phase { case loading, loaded(SavedPlan), failed }

    private(set) var phase: Phase = .loading
    private(set) var error: (any ErrorPresentable)?
    private(set) var isSharing = false
    /// The public link once the server made it; the view shows the share sheet while it is set.
    var shareURL: URL?
    private(set) var shareFailed = false
    var confirmingDelete = false
    private(set) var deleteFailed = false
    /// Set after a delete: the plan no longer exists, so the host leaves the screen.
    private(set) var deleted = false

    /// The plan on screen is the cached copy (the refresh failed).
    private(set) var isOffline = false

    /// The selections with itinerary edits (layout, notes, picked slots) not yet saved; nil = no edits.
    private(set) var draft: JSONValue?
    private(set) var isSavingEdits = false
    private(set) var saveEditsFailed = false
    private(set) var editsSaved = false

    let planID: Int
    private let env: AppEnvironment
    private let files: any FileStore

    init(env: AppEnvironment, planID: Int, files: (any FileStore)? = nil) {
        self.env = env
        self.planID = planID
        self.files = files ?? DiskFileStore.applicationSupport()
    }

    private var username: String? { env.auth.session?.user.username }

    /// One file per plan (`plans-detail/<id>.json`), tagged with the account it belongs to.
    private struct CachedPlan: Codable {
        var username: String?
        var plan: SavedPlan
    }

    private var cachePath: String { "plans-detail/\(planID).json" }

    var plan: SavedPlan? {
        if case .loaded(let plan) = phase { return plan }
        return nil
    }

    func load() async {
        do {
            let plan = try await env.repos.plans.get(id: planID)
            phase = .loaded(plan)
            isOffline = false
            error = nil
            if let data = try? JSONEncoder().encode(CachedPlan(username: username, plan: plan)) {
                try? await files.write(data, to: cachePath)
            }
        } catch is CancellationError {
            return
        } catch APIError.cancelled {
            return
        } catch {
            if plan == nil, let data = try? await files.read(cachePath),
                let cached = try? JSONDecoder().decode(CachedPlan.self, from: data), cached.username == username {
                phase = .loaded(cached.plan)
                isOffline = true
                return
            }
            self.error = error as? any ErrorPresentable
            if plan == nil { phase = .failed }
        }
    }

    // MARK: - Itinerary edits

    /// What the itinerary editor reads: the draft while editing, else the saved selections.
    var selections: JSONValue { draft ?? plan?.selections ?? .null }

    var hasUnsavedEdits: Bool { draft != nil && draft != plan?.selections }

    func setDraft(_ new: JSONValue) {
        // JSONValue is ExpressibleByNilLiteral: a bare `nil` in a ternary would become `.null`, not "no draft".
        if new == plan?.selections { draft = Optional<JSONValue>.none } else { draft = new }
    }

    /// Writes the edited selections to the plan (`PUT /plans/{id}`). Offline or on a failure the draft stays.
    func saveEdits() async {
        guard let draft, hasUnsavedEdits, !isSavingEdits, !isOffline else { return }
        isSavingEdits = true
        defer { isSavingEdits = false }
        do {
            let updated = try await env.repos.plans.update(id: planID, PlanUpdate(selections: draft))
            phase = .loaded(updated)
            self.draft = nil
            editsSaved = true
            // My Plan holds this same plan: keep its selections in step unless it has changes of its own.
            if env.plan.savedPlanID == planID, !env.plan.isDirty { env.plan.load(updated) }
            env.telemetry.track(.featureUsed(feature: "plan_edit_save", page: "plan_detail"))
            if let data = try? JSONEncoder().encode(CachedPlan(username: username, plan: updated)) {
                try? await files.write(data, to: cachePath)
            }
        } catch {
            saveEditsFailed = true
        }
    }

    func clearEditFeedback() {
        saveEditsFailed = false
        editsSaved = false
    }

    // MARK: - Content

    /// The selection fields in display order, each with the section that renders its rows.
    static let fields: [(field: String, section: SectionID)] = [
        ("flight", .flights), ("flights", .flights), ("hotel", .hotels), ("activities", .activities),
        ("places_to_see", .placesToSee), ("walking_tours", .walkingTours), ("events", .events), ("sim", .sim),
        ("tips", .tips), ("getting_around", .gettingAround),
    ]

    /// The picked items per section: a list field gives its items, a single field (`hotel`, `flight`, `sim`) its object.
    static func blocks(for selections: JSONValue) -> [PlanBlock] {
        var order: [SectionID] = []
        var byID: [SectionID: [SectionItem]] = [:]
        for (field, section) in fields {
            let value = selections[field]
            let items: [JSONValue] = value.array ?? (value.object == nil ? [] : [value])
            guard !items.isEmpty else { continue }
            if byID[section] == nil { order.append(section) }
            byID[section, default: []] += items.map(SectionItem.init)
        }
        return order.map { PlanBlock(section: $0, items: byID[$0] ?? []) }
    }

    /// The itinerary snapshot saved with the plan (`{days, total_estimated_cost_usd}`), when it has days.
    static func itinerary(in selections: JSONValue) -> JSONValue? {
        let itinerary = selections["itinerary"]
        guard let days = itinerary["days"].array, !days.isEmpty else { return nil }
        return itinerary
    }

    // MARK: - Actions

    /// Loads the plan into My Plan (`CurrentPlanStore.load`) and opens it. Export lives there (calendar, print).
    func openInMyPlan() {
        guard let plan else { return }
        env.plan.load(plan)
        env.router.open(.myPlan)
    }

    /// Asks the server for the share link; `shareURL` is `<base>/share/<token>`.
    func share() async {
        guard !isSharing else { return }
        isSharing = true
        defer { isSharing = false }
        do {
            let token = try await env.repos.plans.share(id: planID)
            guard let base = env.server.baseURL else {
                shareFailed = true
                return
            }
            shareURL = base.appendingPathComponent("share").appendingPathComponent(token)
            shareFailed = false
        } catch {
            shareFailed = true
        }
    }

    func clearShareFailure() { shareFailed = false }

    func requestDelete() { confirmingDelete = true }

    /// After the confirmation. The server deletes it first; the screen is left only on success.
    @discardableResult
    func confirmDelete() async -> Bool {
        confirmingDelete = false
        do {
            try await env.repos.plans.delete(id: planID)
        } catch {
            deleteFailed = true
            return false
        }
        try? await files.remove(cachePath)
        if env.plan.savedPlanID == planID { env.plan.savedPlanID = nil }
        deleted = true
        return true
    }

    func clearDeleteFailure() { deleteFailed = false }
}
