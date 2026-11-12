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
    public var showsVerification: Bool
    public var searchData: JSONValue?
    public var layout: LayoutClass

    public init(
        isSelected: @escaping @MainActor @Sendable (String, JSONValue) -> Bool,
        toggle: @escaping @MainActor @Sendable (String, JSONValue) -> Void,
        watch: (@MainActor @Sendable (WatchRequest) -> Void)? = nil,
        openURL: @escaping @MainActor @Sendable (URL, String) -> Void,
        showsVerification: Bool = true,
        searchData: JSONValue? = nil,
        layout: LayoutClass = .compact
    ) {
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
