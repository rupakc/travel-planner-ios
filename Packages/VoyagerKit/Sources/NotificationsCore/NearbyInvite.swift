import Foundation

/// An on-device "near you" invite built from the server text catalogue (`nearby_arrival`, `{name}` placeholders;
/// `GET /api/notifications/catalog`). Nothing location-like leaves the device. Task 47 supplies the places.
public enum NearbyInvite {
    /// Fills `{place}`, `{item}` and `{minutes}`; unknown placeholders are left as they are.
    public static func render(template: String, place: String, item: String, minutes: Int) -> String {
        template
            .replacingOccurrences(of: "{place}", with: place)
            .replacingOccurrences(of: "{item}", with: item)
            .replacingOccurrences(of: "{minutes}", with: String(min(max(minutes, 0), 999)))
    }

    public static func notification(id: String, title: String, body: String) -> LocalNotification {
        LocalNotification(id: "nearby-\(id)", title: title, body: body, userInfo: ["route": "nearby"])
    }
}
