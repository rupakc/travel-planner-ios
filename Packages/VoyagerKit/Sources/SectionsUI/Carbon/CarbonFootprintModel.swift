import Domain
import Foundation
import Observation
import VoyagerModel

/// The footprint card's state: debounced requests (350 ms, as on the web) and the remembered diet. A newer request
/// supersedes an older one; while it runs the last answer stays on screen, dimmed.
@MainActor @Observable
public final class CarbonFootprintModel {
    public enum Phase: Equatable, Sendable {
        /// Nothing asked yet (shown as loading: the request follows at once).
        case idle
        case loading
        case loaded
        case failed
        /// `404` (route missing or switched off): the card hides itself.
        case gone
    }

    /// Where the chosen diet is kept (the web's `localStorage` key).
    public static let dietKey = "tp_carbon_diet"

    public private(set) var phase: Phase = .idle
    public private(set) var report: CarbonReport?
    public private(set) var refreshing = false
    public private(set) var diet: String

    @ObservationIgnored private let load: @MainActor @Sendable (JSONValue) async -> CarbonFetch
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sent: JSONValue?
    @ObservationIgnored private var generation = 0

    public init(
        defaults: UserDefaults = .standard,
        debounce: Duration = .milliseconds(350),
        load: @escaping @MainActor @Sendable (JSONValue) async -> CarbonFetch
    ) {
        self.load = load
        self.defaults = defaults
        self.debounce = debounce
        let stored = defaults.string(forKey: Self.dietKey) ?? "mixed"
        diet = CarbonRequest.diets.contains(stored) ? stored : "mixed"
    }

    /// Asks for `body` unless it is what was asked last (or the card is gone for good).
    public func request(_ body: JSONValue) {
        guard phase != .gone, body != sent else { return }
        sent = body
        generation += 1
        let mine = generation
        task?.cancel()
        if report != nil {
            refreshing = true
        } else {
            phase = .loading
        }
        let load = load
        let debounce = debounce
        task = Task { [weak self] in
            do { try await Task.sleep(for: debounce) } catch { return }
            let result = await load(body)
            guard let self, mine == self.generation else { return }
            self.apply(result)
        }
    }

    public func setDiet(_ value: String) {
        guard CarbonRequest.diets.contains(value) else { return }
        diet = value
        defaults.set(value, forKey: Self.dietKey)
    }

    /// The card's lifetime ended (the host disappeared).
    public func cancel() {
        task?.cancel()
        task = nil
        sent = nil
        refreshing = false
    }

    private func apply(_ result: CarbonFetch) {
        refreshing = false
        switch result {
        case .loaded(let value):
            report = value
            phase = .loaded
        case .gone:
            report = nil
            phase = .gone
        case .failed:
            report = nil
            phase = .failed
        }
    }
}
