import Foundation
import L10n
import VoyagerModel

/// The text of an on-device "near you" notification, built from one `POST /nearby` (v1) answer.
///
/// - With a walking time (`minutes`, which v1 items do not carry today) the server template `nearby_arrival`
///   (`{place}`, `{item}`, `{minutes}`) is used, from the cached catalogue or else the bundled English one.
/// - Without one, the place and the top item are shown as they came (backend data, so shown verbatim) under the
///   `mobile:nearYou.fallbackTitle` title. No time is ever made up.
/// - With no usable item at all, the generic `mobile:nearYou.fallbackTitle/Body` copy is used.
public enum NearYouTemplates {
    /// The generic copy; the default reads the `mobile:nearYou.*` catalogue in the app language.
    public struct Copy: Sendable {
        public var fallbackTitle: @Sendable () -> String
        public var fallbackBody: @Sendable () -> String

        public init(fallbackTitle: @escaping @Sendable () -> String, fallbackBody: @escaping @Sendable () -> String) {
            self.fallbackTitle = fallbackTitle
            self.fallbackBody = fallbackBody
        }

        public static let catalogue = Copy(
            fallbackTitle: { L10n.text(K.mobile.nearYou.fallbackTitle) },
            fallbackBody: { L10n.text(K.mobile.nearYou.fallbackBody) })
    }

    public struct Content: Sendable, Equatable {
        public var title: String
        public var body: String
        /// False for the generic invitation.
        public var personalized: Bool
    }

    /// The nearest known place and the top suggestion of an answer.
    public struct Pick: Sendable, Equatable {
        public var place: String
        public var item: String
    }

    static let maxName = 80

    /// The first item with a name; the place may be empty.
    public static func pick(from response: NearbyResponse) -> Pick? {
        for item in response.items ?? [] {
            if let name = clean(item["name"].string) {
                return Pick(place: clean(response.place?.name) ?? "", item: name)
            }
        }
        return nil
    }

    public static func content(
        for response: NearbyResponse, minutes: Int? = nil, catalog: NotificationCatalog? = nil, copy: Copy = .catalogue
    ) -> Content {
        let title = copy.fallbackTitle()
        guard let pick = pick(from: response) else {
            return Content(title: title, body: copy.fallbackBody(), personalized: false)
        }
        if let minutes, !pick.place.isEmpty, let text = render(pick, minutes: minutes, catalog: catalog) {
            return Content(title: title, body: text, personalized: true)
        }
        let body = pick.place.isEmpty ? pick.item : "\(pick.place): \(pick.item)"
        return Content(title: title, body: body, personalized: true)
    }

    /// The `nearby_arrival` text: the catalogue's template when it has one, else the bundled English one.
    static func render(_ pick: Pick, minutes: Int, catalog: NotificationCatalog?) -> String? {
        let key = NotificationTemplateKey.nearbyArrival
        let source = catalog.flatMap { $0.template(key) == nil ? nil : $0 } ?? NotificationCatalog.bundledEnglish
        let values = ["place": pick.place, "item": pick.item, "minutes": String(min(max(minutes, 0), 999))]
        return source.render(key, values).map { String($0.prefix(200)) }
    }

    /// Backend text as one trimmed line of at most `maxName` characters; nil when nothing is left.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : String(line.prefix(maxName))
    }
}
