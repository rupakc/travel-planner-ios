import Domain
import Foundation
import L10n
import Networking
import Observation
import SectionsUI
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// One removable row of My Plan.
struct PlanEntry: Identifiable, Equatable {
    let id: String
    let field: String
    /// Index inside a list field; nil for a single-value field (`flight`, `hotel`, `sim`, `packing_list`).
    let index: Int?
    let title: String
    let subtitle: String?
    let price: Double?
}

/// A titled group of entries (the web's plan modal sections).
struct PlanGroup: Identifiable, Equatable {
    let id: String
    /// The section whose accent tints the header (`SectionAccent`).
    let accent: String
    let icon: String
    let title: String
    let entries: [PlanEntry]
}

/// One slice of the cost breakdown.
struct CostPart: Identifiable, Equatable {
    let key: String
    let label: String
    let amount: Double
    var id: String { key }
}

/// "Under budget" / "over budget" with its text.
struct BudgetNote: Equatable {
    let isOver: Bool
    let label: String
}

/// The plan being built: groups, cost, save, share link and export over `env.plan`.
@MainActor @Observable
final class MyPlanModel {
    private(set) var isSaving = false
    private(set) var isSharing = false
    /// The public link once made; the view presents the share sheet while it is set.
    var shareURL: URL?
    /// The `.ics` file once written; the view presents the share sheet while it is set.
    var calendarFile: URL?
    var toast: ToastMessage?
    var showingSave = false
    var printRequest: PlanPrintRequest?

    let env: AppEnvironment
    @ObservationIgnored private let now: @Sendable () -> Date

    init(env: AppEnvironment, now: @escaping @Sendable () -> Date = { Date() }) {
        self.env = env
        self.now = now
    }

    var isSignedIn: Bool { env.auth.phase == .signedIn }
    var selections: JSONValue { env.plan.selections }
    var searchData: JSONValue { env.plan.searchData ?? .object([:]) }
    var isSaved: Bool { env.plan.savedPlanID != nil }

    /// The name offered in the save sheet: the saved plan's, else the generated one.
    var defaultName: String {
        if let name = env.plan.planName, !name.isEmpty { return name }
        let search = searchData
        return PlanName.generate(
            destination: search["destination"].string ?? "",
            interests: (search["interests"].array ?? []).compactMap(\.string),
            departureDate: search["departure_date"].string)
    }

    var displayName: String { defaultName }

    /// Save and Share need an account; Export works signed out.
    var canSave: Bool { isSignedIn && !isSaving }
    var canShare: Bool { isSignedIn && !isSharing && !isSaving }

    /// "Save" for a plan that was never saved, the web's "Save Changes" once it exists.
    var saveLabel: String { isSaved ? L10n.text(K.plan.modal.save) : L10n.text(K.alerts.ui.save) }

    // MARK: - Content

    /// The itinerary on screen: the live one from Results or Chat, else the snapshot saved with the plan.
    var itinerary: JSONValue? {
        for candidate in [env.plan.latestResults["itinerary"], selections["itinerary"]] {
            if let days = candidate["days"].array, !days.isEmpty { return candidate }
        }
        return nil
    }

    var groups: [PlanGroup] { Self.groups(for: selections) }
    var isEmpty: Bool { groups.isEmpty && itinerary == nil }

    var costParts: [CostPart] { Self.costParts(selections, searchData: searchData) }
    var total: Double { costParts.reduce(0) { $0 + $1.amount } }
    var hasUnpricedTransport: Bool { !(selections["getting_around"].array ?? []).isEmpty }
    var budget: BudgetNote? { Self.budgetNote(total: total, budget: searchData["budget_usd"]) }

    static func costParts(_ selections: JSONValue, searchData: JSONValue) -> [CostPart] {
        (PlanCost.breakdown(selections, searchData: searchData).array ?? []).compactMap { part in
            guard let key = part["key"].string, let amount = part["amount"].double else { return nil }
            return CostPart(key: key, label: part["label"].string ?? key, amount: amount)
        }
    }

    static func budgetNote(total: Double, budget: JSONValue) -> BudgetNote? {
        let detail = PlanCost.budgetStatusDetail(
            cost: total, budget: budget, translate: PlanTranslator.text, locale: LanguageController.current.intlLocale)
        guard let status = detail["status"].string, let label = detail["label"].string else { return nil }
        return BudgetNote(isOver: status == "over", label: label)
    }

    // MARK: - Groups

    private struct Spec {
        let field: String
        let accent: String
        let icon: String
        let single: Bool
    }

    private static let specs: [Spec] = [
        Spec(field: "flight", accent: "flights", icon: "airplane", single: true),
        Spec(field: "flights", accent: "flights", icon: "airplane", single: false),
        Spec(field: "hotel", accent: "hotels", icon: "bed.double", single: true),
        Spec(field: "activities", accent: "activities", icon: "figure.hiking", single: false),
        Spec(field: "places_to_see", accent: "places_to_see", icon: "mappin.and.ellipse", single: false),
        Spec(field: "walking_tours", accent: "walking_tours", icon: "figure.walk", single: false),
        Spec(field: "events", accent: "events", icon: "party.popper", single: false),
        Spec(field: "sim", accent: "sim", icon: "simcard", single: true),
        Spec(field: "tips", accent: "tips", icon: "lightbulb", single: false),
        Spec(field: "getting_around", accent: "getting_around", icon: "bus", single: false),
        Spec(field: "packing_list", accent: "packing_list", icon: "suitcase", single: false),
        Spec(field: "itinerary_slots", accent: "itinerary", icon: "calendar", single: false),
    ]

    static func groups(for selections: JSONValue) -> [PlanGroup] {
        var result: [PlanGroup] = []
        for spec in specs {
            let found = entries(spec, selections[spec.field])
            guard !found.isEmpty else { continue }
            // Single and multi-city flights share one group.
            if spec.field == "flights", let at = result.firstIndex(where: { $0.id == "flight" }) {
                let merged = result[at].entries + found
                result[at] = group("flight", spec, merged)
            } else {
                result.append(group(spec.field, spec, found))
            }
        }
        return result
    }

    private static func group(_ id: String, _ spec: Spec, _ entries: [PlanEntry]) -> PlanGroup {
        let field = id == "flight" && entries.count > 1 ? "flights" : spec.field
        return PlanGroup(
            id: id, accent: spec.accent, icon: spec.icon, title: title(for: field, count: entries.count), entries: entries)
    }

    private static func entries(_ spec: Spec, _ value: JSONValue) -> [PlanEntry] {
        if spec.single { return value.object == nil ? [] : [entry(spec.field, nil, value)] }
        if let list = value.array { return list.enumerated().map { entry(spec.field, $0.offset, $0.element) } }
        // A packing list saved as one object is a single removable row.
        if spec.field == "packing_list", value.object != nil { return [entry(spec.field, nil, value)] }
        return []
    }

    static func title(for field: String, count: Int) -> String {
        let args = ["count": String(count)]
        switch field {
        case "flight": return L10n.text(K.plan.modal.section.flight)
        case "flights": return L10n.text(K.plan.modal.section.flights, count: count)
        case "hotel": return L10n.text(K.plan.modal.section.hotel)
        case "activities": return L10n.text(K.plan.modal.section.activities, args)
        case "places_to_see": return L10n.text(K.plan.print.section.places)
        case "walking_tours": return L10n.text(K.plan.modal.section.walkingTours, args)
        case "events": return L10n.text(K.plan.modal.section.events, args)
        case "sim": return L10n.text(K.plan.modal.section.sim)
        case "tips": return L10n.text(K.plan.modal.section.tips, args)
        case "getting_around": return L10n.text(K.plan.modal.section.gettingAround, args)
        case "packing_list": return SectionID.packingList.title
        default: return L10n.text(K.plan.modal.section.itinerarySlots, args)
        }
    }

    private static func entry(_ field: String, _ index: Int?, _ item: JSONValue) -> PlanEntry {
        let section = SectionItem(item)
        var subtitle: String?
        var title = section.name
        switch field {
        case "flight", "flights":
            let leg = item["outbound"].object == nil ? item : item["outbound"]
            let route = [leg["origin"].string, leg["destination"].string].compactMap { $0 }.filter { !$0.isEmpty }
            let carrier = [leg["airline"].string, leg["flight_number"].string].compactMap { $0 }.filter { !$0.isEmpty }
            title = carrier.isEmpty ? route.joined(separator: " → ") : carrier.joined(separator: " ")
            subtitle = carrier.isEmpty || route.isEmpty ? nil : route.joined(separator: " → ")
        case "hotel":
            if let price = item["price_per_night_usd"].double, price > 0 {
                subtitle = L10n.text(K.plan.modal.hotel.perNight, ["price": CostBreakdownView.usdUpTo2(price)])
            }
        case "itinerary_slots":
            title = title ?? item["activity"].string
            if let day = item["day_number"].double { subtitle = L10n.text(K.plan.modal.day, ["n": String(Int(day))]) }
        default: break
        }
        let name = (title?.isEmpty == false ? title : nil) ?? "–"
        let key = "\(field)-\(index.map(String.init) ?? "one")-\(name)"
        return PlanEntry(id: key, field: field, index: index, title: name, subtitle: subtitle, price: section.priceUSD)
    }

    // MARK: - Remove

    func remove(_ entry: PlanEntry) {
        guard case .object(var object) = selections else { return }
        if let index = entry.index, var list = object[entry.field]?.array, list.indices.contains(index) {
            list.remove(at: index)
            object[entry.field] = .array(list)
        } else {
            object[entry.field] = .null
        }
        env.plan.selections = .object(object)
        env.telemetry.track(.featureUsed(feature: "plan_remove_item", page: "my_plan"))
    }

    // MARK: - Itinerary editing

    /// What the itinerary editor reads and writes: the plan's selections (layout, edits, notes, picked slots)
    /// and the stress-test call, so editing works here exactly as on Results.
    var itineraryHost: ItineraryHost {
        ItineraryHost(
            itinerary: { [weak self] in self?.itinerary },
            selections: { [env] in env.plan.selections },
            setSelections: { [env] in env.plan.selections = $0 },
            recheck: ItineraryHost.recheck(
                agents: env.repos.agents, searchData: env.plan.searchData,
                message: { ($0 as? APIError)?.userFacingDetail }),
            editable: true)
    }

    func itineraryContext(layout: LayoutClass) -> SectionContext {
        var context = SectionContext.inert
        context.searchData = searchData
        context.layout = layout
        return context
    }

    /// Signed out: the way to sign in (the shell shows the login screen on the Trips tab).
    func signIn() {
        env.router.open(.tab(.trips))
    }

    // MARK: - Save

    @discardableResult
    func save(name: String?) async -> Bool {
        guard isSignedIn, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wasSaved = isSaved
        do {
            _ = try await env.plan.save(name: trimmed.isEmpty ? nil : String(trimmed.prefix(200)), using: env.repos.plans)
            env.telemetry.track(.featureUsed(feature: wasSaved ? "plan_update" : "plan_save", page: "my_plan"))
            toast = ToastMessage(L10n.text(K.plan.modal.msg.saved))
            return true
        } catch {
            toast = ToastMessage(L10n.text(K.plan.modal.msg.saveFailed))
            return false
        }
    }

    // MARK: - Share

    /// `<base>/share/<token>`; the base is the server's public URL (`ServerEnvironment` adopts `public_base_url`
    /// from `/api/config` when its host is trusted), else the build's base URL.
    static func shareURL(token: String, base: URL?) -> URL? {
        guard let base else { return nil }
        return base.appendingPathComponent("share").appendingPathComponent(token)
    }

    /// Saves first when there is nothing saved (or unsaved changes), so the link shows what is on screen.
    /// T29 keeps the legacy `POST /plans/{id}/share`; Share 2.0 (`POST /shares`, revoke, My shares) is Phase 4 (4.x).
    func share() async {
        guard isSignedIn, !isSharing, !isSaving else { return }
        if !isSaved || env.plan.isDirty {
            guard await save(name: nil) else { return }
        }
        isSharing = true
        defer { isSharing = false }
        guard let id = env.plan.savedPlanID else { return }
        do {
            let token = try await env.repos.plans.share(id: id)
            guard let url = Self.shareURL(token: token, base: env.server.baseURL) else {
                toast = ToastMessage(L10n.text(K.plan.modal.msg.shareFailed))
                return
            }
            shareURL = url
            env.telemetry.track(.share(target: "system", object: "plan"))
        } catch {
            toast = ToastMessage(L10n.text(K.plan.modal.msg.shareFailed))
        }
    }

    // MARK: - Export

    /// Writes the plan's `.ics` to a temp file and offers it to the share sheet.
    func exportCalendar() async {
        env.telemetry.track(.featureUsed(feature: "plan_export_ics", page: "my_plan"))
        let text = icsText()
        let name = PlanICS.fileName(planName: displayName, ext: "ics")
        let file = await Task.detached(priority: .userInitiated) { () -> URL? in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("plan-export-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(name)
                try Data(text.utf8).write(to: url, options: .atomic)
                return url
            } catch { return nil }
        }.value
        if let file { calendarFile = file } else { toast = ToastMessage(L10n.text(K.errors.generic)) }
    }

    func icsText() -> String {
        PlanICS.build(
            planName: displayName, searchData: searchData, selections: selections, itinerary: itinerary,
            planID: env.plan.savedPlanID, now: now(), labels: PlanExportLabels.live)
    }

    func requestPrint() {
        env.telemetry.track(.featureUsed(feature: "plan_print", page: "my_plan"))
        printRequest = PlanPrintRequest(document: printDocument())
    }

    func printDocument() -> PlanPrintDocument {
        PlanPrintDocument.make(
            name: displayName, searchData: searchData, selections: selections, itinerary: itinerary,
            costParts: costParts, total: total)
    }
}

/// Translates the web-style `"ns:path"` keys the Domain plan helpers emit through the catalogue.
enum PlanTranslator {
    static let text: PlanText = { key, params in
        L10n.text(LKey(key, placeholders: Set(params.keys), plural: false), params)
    }
}

/// The strings inside the `.ics` file, in the app language.
enum PlanExportLabels {
    static var live: PlanICS.Labels {
        PlanICS.Labels(
            dayTheme: { L10n.text(K.plan.ics.dayTheme, ["n": $0, "theme": $1]) },
            fromLinkQuote: { L10n.text(K.plan.ics.fromLinkQuote, ["quote": $0]) },
            fromLink: L10n.text(K.plan.print.fromLink),
            alsoFromLink: { L10n.text(K.plan.print.alsoFromLink, ["names": $0]) },
            estCost: { L10n.text(K.plan.ics.estCost, ["amount": $0]) },
            arrives: { L10n.text(K.plan.ics.arrives, ["time": $0]) },
            booking: { L10n.text(K.plan.ics.booking, ["url": $0]) },
            price: { L10n.text(K.plan.ics.price, ["price": $0]) },
            trip: L10n.text(K.plan.ics.trip),
            defaultName: L10n.text(K.plan.print.defaultName),
            inspiredBy: { L10n.text(K.plan.print.inspiredBy, ["source": $0]) },
            formatCost: { amount in
                amount.formatted(
                    .currency(code: "USD").precision(.fractionLength(0...2)).locale(LanguageController.current.intlLocale))
            })
    }
}
