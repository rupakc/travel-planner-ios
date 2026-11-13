import Domain
import Foundation
import L10n
import SectionsUI
import VoyagerModel

/// What the printed plan shows, built from the plan's selections (the web's `planPrint`): trip line, cost,
/// the picked items per group and the day-by-day itinerary.
struct PlanPrintDocument: Equatable {
    struct Row: Equatable, Identifiable {
        let id: Int
        let title: String
        let detail: String?
        let price: Double?
    }

    struct Block: Equatable, Identifiable {
        let id: String
        let title: String
        let rows: [Row]
    }

    let name: String
    let tripLine: String?
    let inspiredBy: String?
    let total: Double
    let costParts: [CostPart]
    let blocks: [Block]
    let days: [Block]

    static func make(
        name: String, searchData: JSONValue, selections: JSONValue, itinerary: JSONValue?,
        costParts: [CostPart], total: Double
    ) -> PlanPrintDocument {
        let blocks = MyPlanModel.groups(for: selections).filter { $0.id != "itinerary_slots" }.map { group in
            Block(
                id: group.id, title: group.title,
                rows: group.entries.enumerated().map {
                    Row(id: $0.offset, title: $0.element.title, detail: $0.element.subtitle, price: $0.element.price)
                })
        }
        var source: String?
        let importSource = searchData["import_source"]
        if let title = importSource["title"].string ?? importSource["url"].string, !title.isEmpty {
            source = L10n.text(K.plan.print.inspiredBy, ["source": title])
        }
        return PlanPrintDocument(
            name: name, tripLine: tripLine(searchData), inspiredBy: source, total: total, costParts: costParts,
            blocks: blocks, days: itineraryBlocks(selections: selections, itinerary: itinerary))
    }

    static func tripLine(_ search: JSONValue) -> String? {
        let destination = search["destination"].string ?? ""
        guard !destination.isEmpty else { return nil }
        let departure = search["departure_date"].string ?? ""
        let returning = search["return_date"].string ?? ""
        let dates = returning.isEmpty ? departure : "\(departure) – \(returning)"
        let travellers = max(1, Int(search["num_travelers"].double ?? 1))
        return L10n.text(
            K.plan.modal.trip, ["origin": search["origin"].string ?? "", "destination": destination, "dates": dates],
            count: travellers)
    }

    /// The arranged itinerary days with the user's edits applied to each slot's activity and cost.
    static func itineraryBlocks(selections: JSONValue, itinerary: JSONValue?) -> [Block] {
        PlanICS.planItineraryDays(selections: selections, itinerary: itinerary).enumerated().map { offset, day in
            let number = day["day_number"].double.map { String(Int($0)) } ?? String(offset + 1)
            var title = L10n.text(K.plan.modal.day, ["n": number])
            if let theme = day["theme"].string, !theme.isEmpty { title += " · \(theme)" }
            let rows = (day["slots"].array ?? []).enumerated().compactMap { index, slot -> Row? in
                let key = slot["key"].string ?? "\(number)-\(slot["time_of_day"].string ?? "")"
                let edit = selections["itinerary_edits"][key]
                guard let activity = edit["activity"].string ?? slot["activity"].string, !activity.isEmpty else { return nil }
                let cost = edit["cost"].double ?? slot["estimated_cost_usd"].double
                return Row(
                    id: index, title: activity, detail: timeOfDay(slot["time_of_day"].string),
                    price: cost.flatMap { $0 > 0 ? $0 : nil })
            }
            return Block(id: "day-\(offset)", title: title, rows: rows)
        }
    }

    private static func timeOfDay(_ value: String?) -> String? {
        switch value {
        case "morning": L10n.text(K.plan.modal.timeOfDay.morning)
        case "afternoon": L10n.text(K.plan.modal.timeOfDay.afternoon)
        case "evening": L10n.text(K.plan.modal.timeOfDay.evening)
        default: nil
        }
    }
}

/// A print request: a new id each time so the same plan can be printed twice.
struct PlanPrintRequest: Equatable, Identifiable {
    let id = UUID()
    let document: PlanPrintDocument
}
