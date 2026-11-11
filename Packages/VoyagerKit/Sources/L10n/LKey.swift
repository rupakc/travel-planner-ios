import Foundation

/// A typed key into the String Catalog (`<namespace>:<dotted.path>`), generated into `K` (Keys.swift).
public struct LKey: Sendable, Hashable {
    /// `"common:nav.search"`; a plural group's id has no `_one`/`_other` suffix.
    public let id: String
    /// The `{{name}}` placeholders of the English string. A plural key's `count` is not listed:
    /// it is passed as `count:`.
    public let placeholders: Set<String>
    public let plural: Bool

    public init(_ id: String, placeholders: Set<String>, plural: Bool) {
        self.id = id
        self.placeholders = placeholders
        self.plural = plural
    }
}
