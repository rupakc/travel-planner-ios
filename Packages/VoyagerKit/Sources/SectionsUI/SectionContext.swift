import Foundation
import VoyagerModel

/// Compact (iPhone, narrow iPad windows) or regular (wide iPad windows).
public enum LayoutClass: Sendable, Equatable {
    case compact, regular
}

/// What a section needs from its host (Results, Chat, Plan, Share): plan selection, watch creation,
/// link-out, and whether to show verification chips (the chat does not).
public struct SectionContext: Sendable {
    public var isSelected: @MainActor @Sendable (String, JSONValue) -> Bool
    public var toggle: @MainActor @Sendable (String, JSONValue) -> Void
    public var watch: (@MainActor @Sendable (WatchRequest) -> Void)?
    /// `(url, section)`: the host opens the provider page in `SFSafariViewController` and emits `link_out`.
    public var openURL: @MainActor @Sendable (URL, String) -> Void
    /// Re-runs a `/filtered` agent call (`flights`, `hotels`, `activities`) with the sheet's filters; nil hides the
    /// Filters button (chat, shared plans).
    public var filtered: (@MainActor @Sendable (FilterableSection, JSONValue) async -> SectionRemote)?
    /// `POST /api/flights/fare-calendar` for the current search; nil (signed out, chat) hides the strip.
    public var fareCalendar: (@MainActor @Sendable () async -> SectionRemote)?
    public var showsVerification: Bool
    public var searchData: JSONValue?
    public var layout: LayoutClass

    public init(
        isSelected: @escaping @MainActor @Sendable (String, JSONValue) -> Bool,
        toggle: @escaping @MainActor @Sendable (String, JSONValue) -> Void,
        watch: (@MainActor @Sendable (WatchRequest) -> Void)? = nil,
        openURL: @escaping @MainActor @Sendable (URL, String) -> Void,
        filtered: (@MainActor @Sendable (FilterableSection, JSONValue) async -> SectionRemote)? = nil,
        fareCalendar: (@MainActor @Sendable () async -> SectionRemote)? = nil,
        showsVerification: Bool = true,
        searchData: JSONValue? = nil,
        layout: LayoutClass = .compact
    ) {
        self.filtered = filtered
        self.fareCalendar = fareCalendar
        self.isSelected = isSelected
        self.toggle = toggle
        self.watch = watch
        self.openURL = openURL
        self.showsVerification = showsVerification
        self.searchData = searchData
        self.layout = layout
    }

    /// Nothing selected, nothing happens: for previews and tests.
    public static let inert = SectionContext(
        isSelected: { _, _ in false }, toggle: { _, _ in }, openURL: { _, _ in })
}
