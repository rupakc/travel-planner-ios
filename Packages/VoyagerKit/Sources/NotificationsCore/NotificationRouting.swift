import Foundation
import VoyagerModel

/// A notification tap becomes a `Route`. The payload is the notification's `userInfo`: our local notifications
/// set `route` (`alerts`, `trip`, `nearby`), alert rows carry the server's `data` (`watch_id`, `kind`).
public enum NotificationRouting {
    /// `todayAvailable` false (the journey screens are off on this server) sends a trip tap to the trip detail instead.
    public static func route(userInfo: [AnyHashable: Any], todayAvailable: Bool = true) -> Route {
        if userInfo["route"] == nil {
            // A server push (no local `route`): trip kinds open Today, other kinds follow their allow-listed link.
            let push = PushPayload(userInfo: userInfo)
            if let route = push.route(todayAvailable: todayAvailable) { return route }
        }
        var flat: [String: String] = [:]
        for (key, value) in userInfo {
            guard let name = key as? String else { continue }
            if let text = value as? String { flat[name] = text } else if let number = value as? NSNumber {
                flat[name] = number.stringValue
            }
        }
        return route(flat, todayAvailable: todayAvailable)
    }

    public static func route(_ info: [String: String], todayAvailable: Bool = true) -> Route {
        switch info["route"] {
        case "trip":
            if let raw = info["plan_id"], let id = Int(raw), id > 0 {
                return todayAvailable ? .tripToday(planID: id) : .planDetail(id: id)
            }
            return .tab(.trips)
        case "nearby":
            return .nearby
        default:
            let kind = info["kind"].flatMap(WatchKind.init(rawValue:))
            let watch = info["watch_id"].flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            // A push of a kind this app does not know has no watch to open: it lands in the inbox, where it is a generic row.
            if info["route"] == nil, kind == nil, watch == nil, info["kind"] != nil { return .notifications }
            return .alerts(kind: kind, watchID: watch)
        }
    }
}
