import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// What the error card shows and offers, from `detail.code` (the web's `importErrorView`).
public struct ImportErrorView: Equatable, Sendable {
    public enum Action: String, Sendable { case text, images, retry }
    public var code: String
    public var message: String
    public var actions: [Action]
}

public struct ImportShot: Identifiable, Equatable, Sendable {
    public let id: Int
    public let image: ImportImage
}

public struct ImportDraftPlace: Identifiable, Equatable, Sendable {
    public let id: Int
    public var place: ImportPlace
    public var name: String
    public var selected: Bool
    /// The stop (destination name) this place belongs to; nil for an unplaced one until the traveller picks.
    public var destination: String?
}

public struct ImportDraftStop: Identifiable, Equatable, Sendable {
    public var destination: ImportDestination
    public var included = true
    public var nights: Int
    public var id: String { destination.name ?? "" }
}

@MainActor @Observable
public final class ImportModel {
    public enum Phase: Equatable {
        case input
        case loading
        case review
        case failed(ImportErrorView)
    }

    public static let maxMustInclude = 25
    public static let maxStops = 3

    public var text = ""
    public private(set) var shots: [ImportShot] = []
    public private(set) var phase: Phase = .input
    public private(set) var fileProblem: String?
    public private(set) var result: LinkImportResult?
    public var places: [ImportDraftPlace] = []
    public var unplaced: [ImportDraftPlace] = []
    public var stops: [ImportDraftStop] = []
    public var origin = ""
    public var nationality = ""
    public var departure: Date
    public var adults = 1
    /// The failure text of the last "Place it" attempt, by unplaced-place id.
    public private(set) var placeProblems: [Int: String] = [:]
    public private(set) var placing: Set<Int> = []

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var prefilled = false

    public init(env: AppEnvironment, now: Date = Date(), track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
        departure = Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: now) ?? now
    }

    // MARK: Input

    public enum Detected: Equatable {
        case empty
        case url(String)
        case text
    }

    /// A single token that looks like a host (optionally with scheme/path) is a link; anything else is text.
    public var detected: Detected {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return .empty }
        let pattern = #"^(https?://)?([a-z0-9-]+\.)+[a-z]{2,}(:\d+)?([/?#]\S*)?$"#
        let singleToken = value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        let looksLikeHost = value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        if singleToken && looksLikeHost {
            let hasScheme = value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://")
            return .url(hasScheme ? value : "https://\(value)")
        }
        return .text
    }

    public var canFind: Bool {
        phase != .loading && (!shots.isEmpty || detected != .empty)
    }

    public func prefill(url: URL?) async {
        if let url, text.isEmpty { text = url.absoluteString }
        guard !prefilled else { return }
        prefilled = true
        guard let prefs = try? await env.repos.preferences.get() else { return }
        if nationality.isEmpty, let value = prefs.nationality { nationality = value }
        if origin.isEmpty, let value = prefs.currentResidence { origin = value }
        if let count = prefs.adults, count > 0 { adults = count }
    }

    /// Adds picked screenshots (first 4 kept), re-encoding each; a bad file sets `fileProblem`.
    public func addScreenshots(_ datas: [Data]) async {
        fileProblem = nil
        for data in datas {
            guard shots.count < ScreenshotEncoder.maxImages else {
                fileProblem = L10n.text(K.search.import.tooMany, ["max": "\(ScreenshotEncoder.maxImages)", "kept": "\(shots.count)"])
                break
            }
            let encoded = await Task.detached { try? ScreenshotEncoder.encode(data) }.value
            if let encoded {
                nextID += 1
                shots.append(ImportShot(id: nextID, image: encoded))
            } else {
                fileProblem = L10n.text(K.search.import.unreadable, ["name": L10n.text(K.search.import.thatScreenshot)])
            }
        }
    }

    public func removeShot(_ id: Int) { shots.removeAll { $0.id == id } }

    public func useText(_ example: String) { text = example }

    // MARK: Extract

    /// The request for the current input: screenshots win, else a link, else text.
    func extractRequest() -> LinkImportRequest? {
        if !shots.isEmpty { return LinkImportRequest(images: shots.map(\.image)) }
        switch detected {
        case .empty: return nil
        case .url(let url): return LinkImportRequest(url: url)
        case .text: return LinkImportRequest(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func extract() async {
        guard let request = extractRequest(), phase != .loading else { return }
        phase = .loading
        do {
            let preview = try await env.repos.importer.extract(request)
            load(preview)
        } catch is CancellationError {
            phase = .input
        } catch {
            if let api = error as? APIError, case .cancelled = api {
                phase = .input
                return
            }
            phase = .failed(Self.errorView(for: error))
        }
    }

    func load(_ preview: LinkImportResult) {
        result = preview
        var ticked = 0
        places = preview.places.map { place in
            let selected = place.kind != "stay" && ticked < Self.maxMustInclude
            if selected { ticked += 1 }
            return ImportDraftPlace(
                id: newID(), place: place, name: place.name ?? "", selected: selected, destination: place.destination)
        }
        unplaced = preview.unresolved.map {
            ImportDraftPlace(id: newID(), place: $0, name: $0.name ?? "", selected: true, destination: nil)
        }
        stops = preview.destinations.map { ImportDraftStop(destination: $0, nights: max(1, $0.nights ?? 1)) }
        phase = .review
    }

    private func newID() -> Int {
        nextID += 1
        return nextID
    }

    public func startOver() {
        result = nil
        places = []
        unplaced = []
        stops = []
        phase = .input
    }

    /// Back to the input form from an error, switching to what the error card offered.
    public func recover(_ action: ImportErrorView.Action) {
        phase = .input
        if action == .text { shots = [] }
    }

    // MARK: Review

    public var includedStops: [ImportDraftStop] { stops.filter(\.included) }

    func isPlanned(_ place: ImportDraftPlace) -> Bool {
        guard place.selected, let destination = place.destination else { return false }
        return includedStops.contains { $0.id == destination }
    }

    public var plannedCount: Int { min(Self.maxMustInclude, (places + unplaced).filter(isPlanned).count) }

    public var missingField: String? {
        if origin.trimmingCharacters(in: .whitespaces).isEmpty { return L10n.text(K.search.preview.missingOrigin) }
        if nationality.trimmingCharacters(in: .whitespaces).isEmpty { return L10n.text(K.search.preview.missingNationality) }
        return nil
    }

    public var canPlan: Bool { missingField == nil && plannedCount > 0 && !includedStops.isEmpty }

    public func rename(_ id: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = places.firstIndex(where: { $0.id == id }) { places[index].name = trimmed }
        if let index = unplaced.firstIndex(where: { $0.id == id }) { unplaced[index].name = trimmed }
    }

    public func remove(_ id: Int) {
        places.removeAll { $0.id == id }
        unplaced.removeAll { $0.id == id }
    }

    public func toggle(_ id: Int) {
        if let index = places.firstIndex(where: { $0.id == id }) { places[index].selected.toggle() }
        if let index = unplaced.firstIndex(where: { $0.id == id }) { unplaced[index].selected.toggle() }
    }

    public func assign(_ id: Int, stop: String?) {
        if let index = unplaced.firstIndex(where: { $0.id == id }) { unplaced[index].destination = stop }
    }

    public func setNights(_ stop: String, _ nights: Int) {
        if let index = stops.firstIndex(where: { $0.id == stop }) { stops[index].nights = min(30, max(1, nights)) }
    }

    public func setIncluded(_ stop: String, _ included: Bool) {
        if let index = stops.firstIndex(where: { $0.id == stop }) { stops[index].included = included }
    }

    /// "Place it": asks the backend to find the spot in the town the traveller typed, then moves it into its stop.
    public func place(_ id: Int, town: String) async {
        let trimmed = town.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !placing.contains(id), let item = unplaced.first(where: { $0.id == id }) else { return }
        placing.insert(id)
        placeProblems[id] = nil
        defer { placing.remove(id) }
        let request = ResolvePlaceRequest(
            id: item.place.id, name: item.name, kind: item.place.kind, city: trimmed, note: item.place.note,
            quote: item.place.quote)
        do {
            let resolved = try await env.repos.importer.resolvePlace(request)
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let placeJSON = try encoder.encode(resolved["place"])
            let destJSON = try encoder.encode(resolved["destination"])
            let place = try decoder.decode(ImportPlace.self, from: placeJSON)
            let destination = try decoder.decode(ImportDestination.self, from: destJSON)
            let name = destination.name ?? ""
            let known = stops.contains { $0.id == name }
            if !known && stops.count >= Self.maxStops {
                let city = name.split(separator: ",").first.map(String.init) ?? name
                placeProblems[id] = L10n.text(K.search.preview.tooManyStops, ["city": city])
                return
            }
            if !known { stops.append(ImportDraftStop(destination: destination, nights: max(1, destination.nights ?? 1))) }
            unplaced.removeAll { $0.id == id }
            places.append(ImportDraftPlace(id: id, place: place, name: item.name, selected: true, destination: name))
        } catch {
            placeProblems[id] = Self.errorView(for: error).message
        }
    }

    // MARK: Plan

    /// The search the reviewed import feeds (the web's `buildImportSearch`): `must_include` in list order
    /// (at most 25), `import_source`, the last included stop as destination and the other stops as the route.
    public func searchRequest() -> TravelSearchRequest {
        let included = includedStops
        let byName = Dictionary(included.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let chosen = (places + unplaced).filter(isPlanned).prefix(Self.maxMustInclude)
        let mustInclude: [JSONValue] = chosen.map { item in
            let stop = byName[item.destination ?? ""]
            let place = item.place
            let exact = place.approximate != true && place.lat != nil && place.lng != nil
            let stopCity = stop?.destination.city
            let town: JSONValue =
                (place.city != nil && place.city != stopCity) ? .string(place.city ?? "") : .null
            return .object([
                "name": .string(item.name.trimmingCharacters(in: .whitespacesAndNewlines)),
                "kind": .string(place.kind ?? "sight"),
                "city": stopCity.map(JSONValue.string) ?? .null,
                "town": town,
                "lat": exact ? (place.lat.map(JSONValue.number) ?? .null) : .null,
                "lng": exact ? (place.lng.map(JSONValue.number) ?? .null) : .null,
                "note": place.note.map(JSONValue.string) ?? .null,
                "quote": place.quote.map(JSONValue.string) ?? .null,
                "verified": .bool(place.verified == true),
            ])
        }
        let nights = included.reduce(0) { $0 + max(1, $1.nights) }
        var seen = Set<String>()
        let interests = (result?.interests ?? []).filter { seen.insert($0).inserted }
        let source = result?.source
        let importSource: JSONValue = .object([
            "url": source?.kind == "url" ? (source?.url.map(JSONValue.string) ?? .null) : .null,
            "title": (result?.title ?? source?.title).map(JSONValue.string) ?? .null,
        ])
        let multi = included.count > 1
        return TravelSearchRequest(
            origin: origin.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: included.last?.id,
            departureDate: Self.apiDate(departure),
            returnDate: Self.apiDate(
                Calendar(identifier: .gregorian).date(byAdding: .day, value: max(1, nights), to: departure) ?? departure),
            nationality: nationality.trimmingCharacters(in: .whitespacesAndNewlines),
            interests: interests.isEmpty ? nil : interests,
            numTravelers: adults,
            adults: adults,
            destinations: multi ? included.map(\.id) : nil,
            destinationNights: multi ? included.map { Optional($0.nights) } : nil,
            mustInclude: mustInclude,
            importSource: importSource)
    }

    /// Tracks `search_submit(mode: link)` and opens Results for the reviewed import.
    public func plan() {
        guard canPlan else { return }
        let request = searchRequest()
        let nights = includedStops.reduce(0) { $0 + max(1, $1.nights) }
        track(.searchSubmit(mode: .link, travelers: adults, nights: nights, multiCity: includedStops.count > 1))
        env.router.open(.results(request))
    }

    // MARK: Errors

    /// `detail.code` mapped to the web copy; a 413 to "too big"; a 429 shows the backend text; no response is "network".
    static func errorView(for error: any Error) -> ImportErrorView {
        let unknown = L10n.text(K.search.import.err.unknown)
        guard let api = error as? APIError else {
            return ImportErrorView(code: "unknown", message: unknown, actions: [.retry])
        }
        switch api {
        case .network, .interrupted:
            return ImportErrorView(code: "network", message: L10n.text(K.search.import.err.network), actions: [.retry])
        case .rateLimited(let message, _):
            return ImportErrorView(
                code: "rate_limited", message: message.isEmpty ? ErrorCopy.message(kind: .rateLimited, detail: nil) : message,
                actions: [])
        case .client(let status, let detail, let code, _):
            if let code, !code.isEmpty {
                return ImportErrorView(
                    code: code, message: detail?.isEmpty == false ? detail ?? unknown : unknown, actions: actions(for: code))
            }
            if status == 413 {
                return ImportErrorView(
                    code: "too_large", message: detail ?? L10n.text(K.search.import.err.tooLarge), actions: [.images])
            }
            return ImportErrorView(code: "unknown", message: unknown, actions: [.retry])
        case .server(let status, let detail, _):
            if status == 503, let detail, !detail.isEmpty {
                return ImportErrorView(code: "unavailable", message: detail, actions: [.retry])
            }
            return ImportErrorView(code: "unknown", message: unknown, actions: [.retry])
        case .unauthorized:
            return ImportErrorView(
                code: "unauthorized", message: ErrorCopy.message(kind: .unauthorized, detail: nil), actions: [])
        default:
            return ImportErrorView(code: "unknown", message: unknown, actions: [.retry])
        }
    }

    static func actions(for code: String) -> [ImportErrorView.Action] {
        switch code {
        case "blocked_source", "paywall", "blocked_by_site", "empty_page", "unsupported_encoding": [.text, .images]
        case "unsupported_content": [.images]
        case "not_found", "no_places": [.text]
        case "timeout", "unreachable", "http_error": [.retry, .text]
        case "extract_failed": [.retry]
        case "gif_unsupported": [.images]
        default: []
        }
    }

    static func apiDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
