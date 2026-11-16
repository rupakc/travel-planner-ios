import Foundation
import VoyagerModel

struct IdeaFactStat: Equatable {
    enum Key: String { case activities, hotels, places }
    var key: Key
    var count: Int
}

/// What an idea's `snapshot` shows: destinations, trip length, the three counts and the names of the picked items.
/// The server whitelists the snapshot; every key is read defensively and a wrong-typed one is simply absent.
struct IdeaFacts: Equatable {
    typealias Stat = IdeaFactStat

    static let shownItems = 6
    private static let itemGroups = ["activities", "places_to_see", "hotels", "walking_tours", "events"]

    var destinations: [String] = []
    var days: Int = 0
    var stats: [Stat] = []
    var itemNames: [String] = []

    init(snapshot: JSONValue) {
        destinations = (snapshot["destinations"].array ?? []).compactMap(\.string).filter { !$0.isEmpty }
        days = max(0, snapshot["days"].int ?? 0)
        stats = (snapshot["stats"].array ?? []).compactMap { item in
            guard let key = item["key"].string.flatMap(Stat.Key.init(rawValue:)), let count = item["count"].int else {
                return nil
            }
            return Stat(key: key, count: max(0, count))
        }
        itemNames = Self.itemGroups.flatMap { snapshot["items"][$0].array ?? [] }.compactMap { $0["name"].string }.filter { !$0.isEmpty }
    }

    var isEmpty: Bool { destinations.isEmpty && days == 0 && stats.isEmpty && itemNames.isEmpty }
    var shown: [String] { Array(itemNames.prefix(Self.shownItems)) }
    var hiddenCount: Int { max(0, itemNames.count - Self.shownItems) }
}
