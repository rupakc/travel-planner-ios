import Foundation
import Observation

/// The state of one typeahead text field: what the user typed, the value the form sends, and the suggestions.
/// Every edit cancels the previous lookup and starts a new one after the debounce, so only the last query asks the
/// server. A value that is not picked from the list is sent as typed (the backend resolves places by name).
@MainActor @Observable
public final class Typeahead<Item: Sendable> {
    public typealias Fetch = @Sendable (String) async throws -> [Item]

    /// What the field shows.
    public private(set) var text: String
    /// What the form sends: the picked code, else the trimmed text.
    public private(set) var value: String
    public private(set) var isChosen = false
    public private(set) var suggestions: [Item] = []

    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(text: String = "", debounce: Duration = .milliseconds(250), fetch: @escaping Fetch) {
        self.text = text
        value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.debounce = debounce
        self.fetch = fetch
    }

    /// The user typed.
    public func edit(_ newText: String) {
        text = newText
        value = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        isChosen = false
        schedule()
    }

    /// The user picked a suggestion.
    public func choose(text shown: String, value picked: String) {
        task?.cancel()
        task = nil
        text = shown
        value = picked
        isChosen = true
        suggestions = []
    }

    /// The form set the value itself (a recent search, a preference, a prefill): no lookup.
    public func set(external newValue: String) {
        task?.cancel()
        task = nil
        text = newValue
        value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        isChosen = false
        suggestions = []
    }

    public func clear() { set(external: "") }

    /// Waits for the lookup in flight (tests).
    public func settled() async { await task?.value }

    private func schedule() {
        task?.cancel()
        let query = value
        guard query.count >= 2 else {
            task = nil
            suggestions = []
            return
        }
        let wait = debounce
        let fetch = self.fetch
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: wait)
                let found = try await fetch(query)
                guard !Task.isCancelled, let self else { return }
                self.suggestions = found
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { self?.suggestions = [] }
            }
        }
    }
}
