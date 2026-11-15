import Foundation
import VoyagerModel

/// The `data` of a server push (`Notifications-API.md`): `category`, `plan_id`, `kind`, `notification_id`, `group_count`
/// and `link`, read from the notification's `userInfo` (values may arrive as strings or numbers). The title and body are
/// the server's own, already localized text (`aps.alert`), so a grouped push shows its server-written title as it is.
/// Nothing here trusts a field: an unknown kind or category stays nil, a bad number is dropped, text is length-capped.
public struct PushPayload: Sendable, Equatable {
    public var kind: String?
    public var category: NotificationCategory?
    public var planID: Int?
    public var notificationID: Int?
    public var groupCount: Int?
    public var link: String?
    public var title: String?
    public var body: String?

    public init(
        kind: String? = nil, category: NotificationCategory? = nil, planID: Int? = nil, notificationID: Int? = nil,
        groupCount: Int? = nil, link: String? = nil, title: String? = nil, body: String? = nil
    ) {
        self.kind = kind
        self.category = category
        self.planID = planID
        self.notificationID = notificationID
        self.groupCount = groupCount
        self.link = link
        self.title = title
        self.body = body
    }

    public init(userInfo: [AnyHashable: Any]) {
        var flat: [String: Any] = [:]
        for (key, value) in userInfo { if let name = key as? String { flat[name] = value } }
        let kind = Self.text(flat["kind"], limit: 64)
        // Price pushes put the watch kind (`flight`, `hotel`) in `kind`; only a row kind this app knows is kept.
        self.kind = NotificationCategory.of(kind: kind) == nil ? nil : kind
        category = Self.text(flat["category"], limit: 32).flatMap(NotificationCategory.init(rawValue:))
            ?? NotificationCategory.of(kind: self.kind)
        planID = Self.positive(flat["plan_id"])
        notificationID = Self.positive(flat["notification_id"])
        groupCount = Self.positive(flat["group_count"])
        link = Self.text(flat["link"], limit: 256)
        let alert = (flat["aps"] as? [String: Any])?["alert"]
        if let text = alert as? String {
            title = nil
            body = Self.text(text, limit: 300)
        } else if let object = alert as? [String: Any] {
            title = Self.text(object["title"], limit: 300)
            body = Self.text(object["body"], limit: 300)
        }
    }

    /// Where a tap goes; nil leaves the choice to the caller (a price push opens its watch).
    public func route(todayAvailable: Bool = true) -> Route? {
        NotificationTarget.route(kind: kind, planID: planID, link: link, todayAvailable: todayAvailable)
    }

    private static func text(_ value: Any?, limit: Int) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }

    private static func positive(_ value: Any?) -> Int? {
        let number: Int?
        if let text = value as? String, text.count <= 12 { number = Int(text) } else if let raw = value as? NSNumber {
            number = Int(exactly: raw.doubleValue.rounded() == raw.doubleValue ? raw.doubleValue : -1)
        } else { number = nil }
        guard let number, number > 0, number <= 1_000_000_000 else { return nil }
        return number
    }
}
