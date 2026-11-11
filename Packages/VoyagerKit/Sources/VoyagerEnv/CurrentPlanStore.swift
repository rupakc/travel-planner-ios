import Domain
import Foundation
import Observation
import VoyagerModel

/// The plan being built (the web's `selections` + `searchData` of ResultsPage / ChatPage), shared by Results,
/// Chat, My Plan and Trips. Persisted to `current-plan.json` on change (debounced, encoded and written off the
/// main actor) so a relaunch keeps the drawer. Nothing is read from disk until `restore()`.
@MainActor @Observable
public final class CurrentPlanStore {
    public nonisolated static let fileName = "current-plan.json"

    /// A `Selections.empty`-shaped object.
    public var selections: JSONValue = Selections.empty {
        didSet { changed(dirty: true) }
    }

    /// The search the selections came from (a `TravelSearchRequest`-shaped object).
    public var searchData: JSONValue? {
        didSet { changed(dirty: false) }
    }

    /// Section type → data of the latest results (from Results or Chat). Kept in memory only.
    public var latestResults: JSONValue = .object([:])

    /// The saved plan these selections belong to: `save` then updates it instead of creating another.
    public var savedPlanID: Int? {
        didSet { changed(dirty: false) }
    }

    /// The name of the saved plan, when one is loaded or saved.
    public var planName: String? {
        didSet { changed(dirty: false) }
    }

    /// Changed since the last load, save or reset.
    public var isDirty = false

    @ObservationIgnored private let files: any FileStore
    @ObservationIgnored private let persistDelay: Duration
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var lastWrite: Task<Void, Never>?
    /// Bumped by every change; `restore` does not overwrite changes made before it finished.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var applyingRestore = false

    public init(files: any FileStore, persistDelay: Duration = .seconds(1)) {
        self.files = files
        self.persistDelay = persistDelay
    }

    // MARK: - Selections

    /// Toggles `item` in `field` (`Selections.toggle`: dedupes lists, one fare per flight leg).
    public func toggle(field: String, item: JSONValue) {
        selections = Selections.toggle(selections, field: field, item: item)
    }

    public func contains(field: String, item: JSONValue) -> Bool {
        Selections.contains(selections, field: field, item: item)
    }

    // A chat `plan_action` (`set`, `add`, `remove`, `clear`).
    // swiftlint:disable:next large_tuple
    public func apply(planAction: (action: String, field: String, data: JSONValue)) {
        selections = PlanActions.apply(selections, action: planAction.action, field: planAction.field, data: planAction.data)
    }

    /// Opens a saved plan (the web's `handleLoadPlan`): its selections over `Selections.empty`.
    public func load(_ plan: SavedPlan) {
        selections = Self.merged(over: Selections.empty, plan.selections)
        searchData = plan.searchData.isNull ? nil : plan.searchData
        savedPlanID = plan.id
        planName = plan.name
        // The on-screen results belong to another search; the plan carries its own itinerary snapshot.
        latestResults = .object([:])
        isDirty = false
    }

    public func reset() {
        selections = Selections.empty
        searchData = nil
        savedPlanID = nil
        planName = nil
        latestResults = .object([:])
        isDirty = false
    }

    // MARK: - Save

    /// Creates the plan (POST) or, once it has an id, updates it (PUT). A nil `name` keeps the saved name, or
    /// generates one for a new plan (`PlanName.generate`).
    public func save(name: String?, using plans: any PlansRepository) async throws -> SavedPlan {
        let startRevision = revision
        let body = Self.selectionsForSave(selections, latestResults: latestResults)
        let saved: SavedPlan
        if let id = savedPlanID {
            saved = try await plans.update(id: id, PlanUpdate(name: name, selections: body))
        } else {
            let search = searchData ?? .object([:])
            let generated = PlanName.generate(
                destination: search["destination"].string ?? "",
                interests: (search["interests"].array ?? []).compactMap(\.string),
                departureDate: search["departure_date"].string)
            saved = try await plans.create(NewPlan(name: name ?? planName ?? generated, searchData: search, selections: body))
        }
        let untouched = revision == startRevision
        savedPlanID = saved.id
        planName = saved.name
        if untouched { isDirty = false }
        return saved
    }

    /// The web's `selectionsForSave`: the selections without this search's link evidence, plus a snapshot of the
    /// live itinerary (`{days, total_estimated_cost_usd}`) so the share page can show the whole schedule.
    /// The snapshot is the itinerary as generated; readers arrange it with `itinerary_layout` / `itinerary_edits`,
    /// which travel in the same selections, exactly like the web.
    public static func selectionsForSave(_ selections: JSONValue, latestResults: JSONValue) -> JSONValue {
        let saved = Selections.strippingLinkEvidence(selections)
        let itinerary = latestResults["itinerary"]
        guard let days = itinerary["days"].array, !days.isEmpty, case .object(var object) = saved else { return saved }
        var snapshot: [String: JSONValue] = ["days": .array(days)]
        let total = itinerary["total_estimated_cost_usd"]
        if !total.isNull { snapshot["total_estimated_cost_usd"] = total }
        object["itinerary"] = .object(snapshot)
        return .object(object)
    }

    static func merged(over base: JSONValue, _ overlay: JSONValue) -> JSONValue {
        guard case .object(var result) = base, case .object(let extra) = overlay else { return base }
        for (key, value) in extra { result[key] = value }
        return .object(result)
    }

    // MARK: - Persistence

    private struct Persisted: Codable, Sendable {
        var selections: JSONValue
        var searchData: JSONValue?
        var savedPlanID: Int?
        var planName: String?
        var isDirty: Bool
    }

    private func changed(dirty: Bool) {
        guard !applyingRestore else { return }
        revision += 1
        if dirty { isDirty = true }
        schedulePersist()
    }

    private func schedulePersist() {
        pendingWrite?.cancel()
        let delay = persistDelay
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    private func writeNow() {
        pendingWrite = nil
        let snapshot = Persisted(
            selections: selections, searchData: searchData, savedPlanID: savedPlanID, planName: planName, isDirty: isDirty)
        let files = files
        let previous = lastWrite
        lastWrite = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? await files.write(data, to: Self.fileName)
        }
    }

    /// Writes a pending change now and waits for every write (tests, and before the app is suspended).
    public func flushPersistence() async {
        if pendingWrite != nil {
            pendingWrite?.cancel()
            writeNow()
        }
        await lastWrite?.value
    }

    /// Reads `current-plan.json` (off the main actor). Changes made before it finishes win over the file.
    public func restore() async {
        let startRevision = revision
        let files = files
        let restored = await Task.detached(priority: .utility) { () -> Persisted? in
            guard let data = try? await files.read(Self.fileName) else { return nil }
            return try? JSONDecoder().decode(Persisted.self, from: data)
        }.value
        guard let restored, revision == startRevision else { return }
        applyingRestore = true
        selections = Self.merged(over: Selections.empty, restored.selections)
        searchData = restored.searchData
        savedPlanID = restored.savedPlanID
        planName = restored.planName
        isDirty = restored.isDirty
        applyingRestore = false
    }
}
