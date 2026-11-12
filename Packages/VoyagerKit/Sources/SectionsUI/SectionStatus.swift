import Foundation

/// A section's progress. Mirrors the web's `statuses[agent]`: `waiting` (nothing yet, hidden), `loading`,
/// `enhancing` (static data shown while the AI refines it), `done`, and an error with the message to show.
public enum SectionStatus: Equatable, Sendable {
    case waiting, loading, enhancing, done, error(String)

    /// The web's status word. `error` has no message here, so it maps to `.error("")` (generic copy).
    public init?(webWord: String) {
        switch webWord {
        case "waiting": self = .waiting
        case "loading": self = .loading
        case "enhancing": self = .enhancing
        case "done": self = .done
        case "error": self = .error("")
        default: return nil
        }
    }

    /// The status a streamed result gets from its `source`: static data is "enhancing", AI data is "done".
    public init(source: String?) {
        self = source == "static" ? .enhancing : .done
    }

    /// Whether the section has data to show (the web's `done || enhancing`).
    public var isReady: Bool {
        switch self {
        case .done, .enhancing: true
        default: false
        }
    }

    /// The web renders nothing for a section that is still `waiting`.
    public var isVisible: Bool { self != .waiting }
}
