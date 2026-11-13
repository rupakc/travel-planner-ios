import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// `GET/PUT /api/preferences`: the editable draft, load and save. PUT replaces every field, so the draft always
/// sends all of them (the traveller total is derived, like the web).
@MainActor @Observable
final class PreferencesModel {
    enum Phase { case loading, loaded, failed }
    enum SaveStatus: Equatable { case none, saved, failed(detail: String?) }

    nonisolated static let budgets = ["low", "medium", "high"]
    nonisolated static let interestIDs = [
        "food", "history", "adventure", "culture", "nature", "shopping", "nightlife", "wellness", "art", "family",
    ]
    nonisolated static let accessIDs = ["wheelchair", "visual_impairment", "hearing_impairment", "cognitive_disability"]
    nonisolated static let maxPerGroup = 20

    private let env: AppEnvironment
    @ObservationIgnored private let track: (TelemetryEvent) -> Void

    private(set) var phase = Phase.loading
    private(set) var loadError: (any ErrorPresentable)?
    private(set) var saving = false
    private(set) var saveStatus = SaveStatus.none

    var budget = "medium"
    var nationality = ""
    var residence = ""
    var permits: [String] = []
    var visas: [String] = []
    var interests: [String] = []
    var adults = 1
    var children = 0
    var seniors = 0
    var infants = 0
    var access: [String] = []

    private var pickedNationality: String?
    private(set) var nationalitySuggestions: [NationalitySuggestion] = []

    init(env: AppEnvironment, track: ((TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.track = track ?? { env.telemetry.track($0) }
    }

    // MARK: - Load

    func load() async {
        phase = .loading
        loadError = nil
        do {
            apply(try await env.repos.preferences.get())
            phase = .loaded
        } catch {
            loadError = (error as? any ErrorPresentable) ?? PreferencesFailure()
            phase = .failed
        }
    }

    func apply(_ prefs: Preferences) {
        budget = prefs.budgetCategory ?? "medium"
        nationality = prefs.nationality ?? ""
        residence = prefs.currentResidence ?? ""
        permits = prefs.residencePermits ?? []
        visas = prefs.existingVisas ?? []
        interests = prefs.interests ?? []
        access = prefs.accessibilityNeeds ?? []
        if prefs.adults == nil, prefs.children == nil, prefs.seniors == nil, prefs.infants == nil {
            adults = max(1, min(prefs.numTravelers ?? 1, Self.maxPerGroup))
            children = 0
            seniors = 0
            infants = 0
        } else {
            adults = Self.clamp(prefs.adults)
            children = Self.clamp(prefs.children)
            seniors = Self.clamp(prefs.seniors)
            infants = Self.clamp(prefs.infants)
        }
    }

    private static func clamp(_ value: Int?) -> Int { min(max(value ?? 0, 0), maxPerGroup) }

    // MARK: - Save

    var totalTravelers: Int { max(1, adults + children + seniors + infants) }

    /// Every field, as the PUT sends it.
    func draft() -> Preferences {
        Preferences(
            budgetCategory: budget,
            nationality: nationality.trimmingCharacters(in: .whitespacesAndNewlines),
            currentResidence: residence.trimmingCharacters(in: .whitespacesAndNewlines),
            residencePermits: permits,
            existingVisas: visas,
            interests: interests,
            numTravelers: totalTravelers,
            adults: adults,
            children: children,
            seniors: seniors,
            infants: infants,
            accessibilityNeeds: access)
    }

    func save() async {
        guard !saving, phase == .loaded else { return }
        saving = true
        saveStatus = .none
        do {
            apply(try await env.repos.preferences.put(draft()))
            saveStatus = .saved
            track(.featureUsed(feature: "prefs_save", page: "preferences"))
        } catch {
            let detail = (error as? any ErrorPresentable)?.userFacingDetail
            saveStatus = .failed(detail: detail)
        }
        saving = false
    }

    var saveFailed: Bool {
        if case .failed = saveStatus { return true }
        return false
    }

    var saveMessage: String? {
        switch saveStatus {
        case .none: return nil
        case .saved: return L10n.text(K.account.prefs.saved)
        case .failed(let detail):
            if let detail, !detail.isEmpty { return L10n.text(K.account.prefs.errorWithDetail, ["detail": detail]) }
            return L10n.text(K.account.prefs.saveFailed)
        }
    }

    // MARK: - Editing

    func toggleInterest(_ id: String) { interests = Self.toggled(interests, id) }
    func toggleAccess(_ id: String) { access = Self.toggled(access, id) }

    private static func toggled(_ list: [String], _ id: String) -> [String] {
        list.contains(id) ? list.filter { $0 != id } : list + [id]
    }

    func addTag(_ text: String, to keyPath: ReferenceWritableKeyPath<PreferencesModel, [String]>) {
        let tag = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !self[keyPath: keyPath].contains(tag) else { return }
        self[keyPath: keyPath].append(tag)
    }

    func removeTag(_ text: String, from keyPath: ReferenceWritableKeyPath<PreferencesModel, [String]>) {
        self[keyPath: keyPath].removeAll { $0 == text }
    }

    func setCount(_ group: TravelerGroup, _ value: Int) {
        let next = min(max(value, 0), Self.maxPerGroup)
        switch group {
        case .adults: adults = next
        case .children: children = next
        case .seniors: seniors = next
        case .infants: infants = next
        }
    }

    func count(_ group: TravelerGroup) -> Int {
        switch group {
        case .adults: adults
        case .children: children
        case .seniors: seniors
        case .infants: infants
        }
    }

    // MARK: - Nationality typeahead

    func searchNationalities(_ query: String) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text != pickedNationality else {
            nationalitySuggestions = []
            return
        }
        let found = (try? await env.repos.reference.nationalities(text, limit: 6)) ?? []
        if !Task.isCancelled { nationalitySuggestions = found }
    }

    func pickNationality(_ suggestion: NationalitySuggestion) {
        nationality = suggestion.nationality ?? suggestion.country ?? nationality
        pickedNationality = nationality.trimmingCharacters(in: .whitespacesAndNewlines)
        nationalitySuggestions = []
    }
}

enum TravelerGroup: String, CaseIterable, Sendable { case adults, seniors, children, infants }

struct PreferencesFailure: ErrorPresentable {
    var presentationKind: ErrorPresentationKind { .other }
    var userFacingDetail: String? { nil }
}
