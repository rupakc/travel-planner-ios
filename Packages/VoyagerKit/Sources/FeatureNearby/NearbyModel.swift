import Domain
import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// One place in a group.
public struct NearbyRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String?
    public var mapsURL: URL?
}

/// One group of places (see / eat / shop / stay in v2; a single "around you" group in v1).
public struct NearbyGroup: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var emptyText: String?
    public var rows: [NearbyRow]
}

/// What a finished lookup shows. Held in memory only: nothing about it is ever written to disk.
public struct NearbyResult: Equatable, Sendable {
    public var placeName: String
    public var groups: [NearbyGroup]
    public var attribution: String?
    public var sources: [NearbySource]
    public var isV2: Bool

    public var count: Int { groups.reduce(0) { $0 + $1.rows.count } }
}

/// Near me: asks for when-in-use location on this screen (after an explanation), looks places up with
/// `POST /api/nearby` (`sections: true`) and falls back to the v1 item list when the v2 fields are absent.
@MainActor @Observable
public final class NearbyModel {
    public enum Phase: Equatable {
        case intro
        case denied
        case locating
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .intro
    public private(set) var result: NearbyResult?

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let location: any LocationProviding
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var started = false

    public init(
        env: AppEnvironment, location: any LocationProviding, track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.location = location
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
    }

    /// The system Settings page of this app (for the denied state), where there is one.
    public var settingsURL: URL? {
        #if canImport(UIKit)
        URL(string: "app-settings:")
        #else
        nil
        #endif
    }

    public var isBusy: Bool { phase == .locating || phase == .loading }

    /// On first appearance: a user who already allowed location goes straight to the lookup; one who denied
    /// sees the Settings hint; anyone else sees the explanation first.
    public func begin() async {
        guard !started else { return }
        started = true
        switch location.access {
        case .allowed: await load()
        case .denied: phase = .denied
        case .notDetermined: phase = .intro
        }
    }

    /// "Use my location": the system prompt, then the lookup.
    public func useLocation() async {
        guard !isBusy else { return }
        switch await location.requestAccess() {
        case .allowed: await load()
        case .denied: phase = .denied
        case .notDetermined: phase = .intro
        }
    }

    /// One coarse reading (rounded to about 100 m before it leaves the device), then the lookup.
    public func load() async {
        run += 1
        let token = run
        phase = .locating
        let coordinate: Coordinate
        do {
            coordinate = try await location.currentCoordinate()
        } catch {
            guard token == run else { return }
            switch error as? LocationFailure {
            case .denied: phase = .denied
            case .timeout: phase = .failed(L10n.text(K.misc.nearby.geo.timeout))
            default: phase = .failed(L10n.text(K.misc.nearby.geo.unavailable))
            }
            return
        }
        guard token == run else { return }
        phase = .loading
        let request = NearbyRequest(
            lat: Self.rounded(coordinate.lat), lng: Self.rounded(coordinate.lng), sections: true,
            language: env.language.language.rawValue)
        do {
            let response = try await env.repos.nearby.nearby(request)
            guard token == run else { return }
            result = Self.result(from: response)
            phase = .loaded
        } catch {
            guard token == run else { return }
            phase = .failed(Self.reason(for: error))
        }
    }

    // MARK: Plan and links

    public func isInPlan(_ row: NearbyRow) -> Bool {
        env.plan.contains(field: Self.planField, item: Self.planItem(row))
    }

    /// Adds the place to the active plan's places (or removes it again).
    public func togglePlan(_ row: NearbyRow) {
        let item = Self.planItem(row)
        if !env.plan.contains(field: Self.planField, item: item) {
            track(.planSelect(section: Self.planField))
        }
        env.plan.toggle(field: Self.planField, item: item)
    }

    /// Telemetry for "Open in Maps": the host only, never the place.
    public func didOpenMaps(_ row: NearbyRow) {
        guard let host = row.mapsURL?.host()?.lowercased() else { return }
        track(.linkOut(section: "nearby", domain: host))
    }

    // MARK: Pure helpers

    static let planField = "places_to_see"

    static func planItem(_ row: NearbyRow) -> JSONValue {
        var object: [String: JSONValue] = ["name": .string(row.name), "source": .string("nearby")]
        if let summary = row.summary { object["description"] = .string(summary) }
        if let url = row.mapsURL { object["maps_uri"] = .string(url.absoluteString) }
        return .object(object)
    }

    static func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

    /// v2 when `sections` is present, else the v1 `items` as one group.
    static func result(from response: NearbyResponse) -> NearbyResult {
        let placeName = response.place?.name ?? L10n.text(K.misc.nearby.you)
        if let sections = response.sections {
            let groups = sections.enumerated().map { index, section -> NearbyGroup in
                let id = section.id ?? "section\(index)"
                let rows = section.items.enumerated().compactMap { itemIndex, item -> NearbyRow? in
                    guard let name = item.name, !name.isEmpty else { return nil }
                    return NearbyRow(
                        id: "\(id)-\(itemIndex)", name: name, summary: item.summary,
                        mapsURL: mapsURL(uri: item.mapsUri, name: name, near: placeName))
                }
                return NearbyGroup(id: id, title: title(id: id, fallback: section.title), emptyText: empty(id: id), rows: rows)
            }
            return NearbyResult(
                placeName: placeName, groups: groups, attribution: response.attribution,
                sources: response.sources ?? [], isV2: true)
        }
        let rows = (response.items ?? []).enumerated().compactMap { index, item -> NearbyRow? in
            guard let name = item["name"].string, !name.isEmpty else { return nil }
            return NearbyRow(
                id: "around-\(index)", name: name, summary: item["description"].string,
                mapsURL: mapsURL(uri: item["maps_uri"].string, name: name, near: placeName))
        }
        let group = NearbyGroup(id: "around", title: L10n.text(K.misc.nearby.aroundYou), emptyText: nil, rows: rows)
        return NearbyResult(placeName: placeName, groups: [group], attribution: nil, sources: [], isV2: false)
    }

    static func title(id: String, fallback: String?) -> String {
        switch id {
        case "see": L10n.text(K.misc.nearby.section.see)
        case "eat": L10n.text(K.misc.nearby.section.eat)
        case "shop": L10n.text(K.misc.nearby.section.shop)
        case "stay": L10n.text(K.misc.nearby.section.stay)
        default: fallback ?? id
        }
    }

    static func empty(id: String) -> String? {
        switch id {
        case "see": L10n.text(K.misc.nearby.empty.see)
        case "eat": L10n.text(K.misc.nearby.empty.eat)
        case "shop": L10n.text(K.misc.nearby.empty.shop)
        case "stay": L10n.text(K.misc.nearby.empty.stay)
        default: nil
        }
    }

    /// The backend's Maps link when it is an https URL, else a Google Maps search for the place.
    static func mapsURL(uri: String?, name: String, near place: String) -> URL? {
        if let uri, let url = URL(string: uri), url.scheme?.lowercased() == "https", url.host() != nil { return url }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: "\(name) \(place)"),
        ]
        return components?.url
    }

    /// The backend's own text when it sent one (the 503 `grounding_unavailable` text), else the web copy.
    static func reason(for error: any Error) -> String {
        if let api = error as? APIError {
            if let detail = api.userFacingDetail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                return detail
            }
            if case .server(let status, _, _) = api, status == 503 { return L10n.text(K.misc.nearby.api.grounding_unavailable) }
            if case .network = api { return L10n.text(K.misc.nearby.api.network) }
        }
        return L10n.text(K.misc.nearby.apiErrorTitle)
    }

    /// Shows a state without a lookup (snapshot tests).
    func show(phase: Phase, result: NearbyResult? = nil) {
        self.phase = phase
        self.result = result
        started = true
    }
}
