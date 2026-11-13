import Foundation
import VoyagerModel

/// A notification tap becomes a `Route`. The payload is the notification's `userInfo`: our local notifications
/// set `route` (`alerts`, `trip`, `nearby`), alert rows carry the server's `data` (`watch_id`, `kind`).
public enum NotificationRouting {
    public static func route(userInfo: [AnyHashable: Any]) -> Route {
        var flat: [String: String] = [:]
        for (key, value) in userInfo {
            guard let name = key as? String else { continue }
            if let text = value as? String { flat[name] = text } else if let number = value as? NSNumber {
                flat[name] = number.stringValue
            }
        }
        return route(flat)
    }

    public static func route(_ info: [String: String]) -> Route {
        switch info["route"] {
        case "trip":
            if let raw = info["plan_id"], let id = Int(raw), id > 0 { return .planDetail(id: id) }
            return .tab(.trips)
        case "nearby":
            return .nearby
        default:
            let kind = info["kind"].flatMap(WatchKind.init(rawValue:))
            let watch = info["watch_id"].flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            return .alerts(kind: kind, watchID: watch)
        }
    }
}
