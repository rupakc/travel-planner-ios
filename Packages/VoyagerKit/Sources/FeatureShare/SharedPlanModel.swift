import AuthCore
import Foundation
import Networking
import Observation
import SectionsUI
import VoyagerEnv
import VoyagerModel

/// The public share viewer's state (`GET /api/share/{token}`, no sign-in needed) and its one action, Remix.
@MainActor @Observable
public final class SharedPlanModel {
    public enum State: Equatable {
        case loading
        case loaded(SharedPlan)
        /// 404: unknown or revoked token, or sharing switched off (the web's "not available" copy).
        case notFound
        /// Any other failure; `detail` is the server's own text when it sent one.
        case failed(detail: String?, kind: ErrorPresentationKind)
    }

    public private(set) var state: State = .loading
    /// Set when "Remix" was tapped while signed out: the view then offers sign-in.
    public private(set) var needsSignIn = false

    public let token: String
    @ObservationIgnored private let env: AppEnvironment

    public init(env: AppEnvironment, token: String) {
        self.env = env
        self.token = token
    }

    public var plan: SharedPlan? {
        if case .loaded(let plan) = state { return plan }
        return nil
    }

    public var isSignedIn: Bool { env.auth.phase == .signedIn }

    public func load() async {
        state = .loading
        do {
            state = .loaded(try await env.repos.plans.shared(token: token))
        } catch let error as APIError {
            if case .notFound = error {
                state = .notFound
            } else if case .cancelled = error {
                return
            } else {
                state = .failed(detail: error.userFacingDetail, kind: error.presentationKind)
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(detail: nil, kind: .other)
        }
    }

    /// Shows `plan` without loading (snapshots).
    func show(_ plan: SharedPlan) { state = .loaded(plan) }

    // MARK: - Derived content

    /// The sections to show, in the web's order, each as the data shape its `SectionsUI` view reads.
    /// Only a plan share has them (a recap or savings share is a card).
    public var sections: [(id: SectionID, data: JSONValue)] {
        guard let plan, !isCard else { return [] }
        return Self.sections(from: plan.selections)
    }

    nonisolated static func sections(from selections: JSONValue) -> [(id: SectionID, data: JSONValue)] {
        func list(_ key: String) -> [JSONValue] { selections[key].array ?? [] }
        var out: [(SectionID, JSONValue)] = []
        if selections["itinerary"]["days"].array?.isEmpty == false {
            out.append((.itinerary, selections["itinerary"]))
        }
        var flights = list("flights")
        if flights.isEmpty, selections["flight"].object != nil { flights = [selections["flight"]] }
        if !flights.isEmpty { out.append((.flights, ["flights": .array(flights)])) }
        if selections["hotel"].object != nil { out.append((.hotels, ["hotels": [selections["hotel"]]])) }
        let lists: [(SectionID, String, String)] = [
            (.activities, "activities", "activities"), (.placesToSee, "places_to_see", "places"),
            (.events, "events", "events"), (.walkingTours, "walking_tours", "tours"),
        ]
        for (id, field, key) in lists where !list(field).isEmpty { out.append((id, [key: .array(list(field))])) }
        if selections["sim"].object != nil { out.append((.sim, ["plans": [selections["sim"]]])) }
        if !list("tips").isEmpty { out.append((.tips, ["tips": .array(list("tips"))])) }
        if !list("getting_around").isEmpty { out.append((.gettingAround, ["options": .array(list("getting_around"))])) }
        return out.map { (id: $0.0, data: $0.1) }
    }

    /// A recap or savings share (Phase 4): `kind` plus a `card`, no plan body.
    public var isCard: Bool {
        guard let plan, plan.card != nil else { return false }
        return plan.kind == "recap" || plan.kind == "savings"
    }

    public var title: String? {
        guard let name = plan?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    public var destination: String? { nonEmpty(plan?.searchData["destination"].string) }
    public var origin: String? { nonEmpty(plan?.searchData["origin"].string) }

    public var travelers: Int? {
        guard let value = plan?.searchData["num_travelers"].int, value > 0 else { return nil }
        return value
    }

    /// "Inspired by …": the page's title, else its host. `url` only when it is a plain https link.
    public var inspiredBy: (label: String, url: URL?)? {
        guard let source = plan?.searchData["import_source"], source.object != nil else { return nil }
        let url = source["url"].string.flatMap(URL.init(string:)).flatMap { Self.isHTTPS($0) ? $0 : nil }
        guard let label = nonEmpty(source["title"].string) ?? url?.host() else { return nil }
        return (label, url)
    }

    public var ownerName: String? { nonEmpty(plan?.ownerName) }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host()?.isEmpty ?? true)
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Remix

    /// Signed in: copies the shared plan into My Plan (an unsaved draft, never someone else's plan id) and opens
    /// it. Signed out: nothing is copied; `needsSignIn` asks the view for sign-in first.
    public func remix() {
        guard let plan, !isCard else { return }
        guard isSignedIn else {
            needsSignIn = true
            return
        }
        needsSignIn = false
        env.plan.load(
            SavedPlan(id: 0, name: title ?? "", searchData: plan.searchData, selections: plan.selections))
        env.plan.savedPlanID = nil
        env.plan.planName = title
        env.plan.isDirty = true
        env.router.open(.myPlan)
    }

    /// Signed out, the way to sign-in: leaves the viewer (the shell shows the login screen).
    public func signIn() {
        env.router.open(.tab(.trips))
    }
}
