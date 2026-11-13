import DesignSystem
import SnapshotTesting
import SwiftUI
import TestFixtures
import VoyagerModel
import XCTest

@testable import SectionsUI

/// The commerce sections on the `search_full.sse` data: iPhone SE and iPad, light and dark, one German AX5 shot.
@MainActor
final class CommerceSnapshotTests: XCTestCase {
    private let phone: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 1500)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 1500)),
    ]
    private let pad: [SnapshotConfig] = [
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 1500)),
        SnapshotConfig(name: "ipad-dark", device: .iPadPro11(.portrait), dark: true, canvas: CGSize(width: 834, height: 1500)),
    ]
    /// The last payload per section type in the fixture (the verified hotels replace the first ones).
    private static let payloads: [String: JSONValue] = {
        var found: [String: JSONValue] = [:]
        guard let lines = try? Fixtures.sseDataLines("sse/search_full.sse") else { return found }
        for line in lines {
            guard let event = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
                let type = event["type"].string, event["data"].object != nil
            else { continue }
            found[type] = event["data"]
        }
        return found
    }()

    private func data(_ type: String) -> JSONValue { Self.payloads[type] ?? .null }

    /// A far-future trip so Watch is offered whatever day CI runs.
    private var ctx: SectionContext {
        SectionContext(
            isSelected: { field, item in field == "flights" && item["price_usd"].double == 1200 },
            toggle: { _, _ in }, watch: { _ in }, openURL: { _, _ in },
            searchData: ["origin": "NYC", "destination": "Tokyo", "departure_date": "2099-04-01", "return_date": "2099-04-08", "num_travelers": 2],
            layout: .compact)
    }

    private var padCtx: SectionContext {
        var copy = ctx
        copy.layout = .regular
        return copy
    }

    private func check<V: View>(_ name: String, configs: [SnapshotConfig]? = nil, view: @MainActor (SectionContext) -> V) {
        assertSnapshots(of: { view(ctx) }, named: name, configs: configs ?? phone)
        if configs == nil { assertSnapshots(of: { view(padCtx) }, named: name, configs: pad) }
    }

    func test_flights() {
        var flights = data("flights")
        if case .object(var object) = flights {
            object["price_insights"] = ["price_level": "low", "typical_price_range": [900, 1500]]
            flights = .object(object)
        }
        let shown = flights
        check("flights") { FlightsSectionView(data: shown, ctx: $0) }
    }

    func test_flightsMultiCity() {
        let live: JSONValue = data("flights")["results"][0]
        let multi: JSONValue = [
            "trip_type": "multi_city",
            "legs": [
                ["leg_index": 0, "label": "NYC → Tokyo", "results": [live]],
                ["leg_index": 1, "label": "Tokyo → Seoul", "results": []],
            ],
            "results": [live],
        ]
        check("flights-multi") { FlightsSectionView(data: multi, ctx: $0) }
    }

    func test_hotels() {
        check("hotels") { HotelsSectionView(data: data("hotels"), ctx: $0) }
    }

    func test_activities() {
        var activities = data("activities")
        if case .object(var object) = activities, var results = object["results"]?.array {
            results.append(["name": "Hidden izakaya crawl", "category": "food", "price_usd": 60, "from_link": true, "source": "web"])
            object["results"] = .array(results)
            activities = .object(object)
        }
        let shown = activities
        check("activities") { ActivitiesSectionView(data: shown, ctx: $0) }
    }

    func test_sim() {
        check("sim") { SimSectionView(data: data("sim"), ctx: $0) }
    }

    func test_pricingAdvisor() {
        var pricing = data("pricing_advisor")
        if case .object(var object) = pricing {
            object["price_status_label"] = "Typical price"
            object["confidence"] = "medium"
            object["trend_data"] = [
                ["days_before": 90, "relative_price": 1.0], ["days_before": 60, "relative_price": 0.9],
                ["days_before": 30, "relative_price": 0.95], ["days_before": 7, "relative_price": 1.2],
            ]
            pricing = .object(object)
        }
        let shown = pricing
        check("pricing") { PricingAdvisorView(data: shown, ctx: $0) }
    }

    func test_fareCalendarStrip() {
        let dates: [JSONValue] = [
            ["departure_date": "2099-03-29", "cheapest_usd": 1300],
            ["departure_date": "2099-03-30", "cheapest_usd": 1180],
            ["departure_date": "2099-04-01", "cheapest_usd": 1200, "is_selected": true],
            ["departure_date": "2099-04-02", "cheapest_usd": nil],
        ]
        check("fare-calendar") { _ in
            FareCalendarStrip(load: { .loaded(["dates": .array(dates)]) }, onUnavailable: {}, initial: .loaded(dates))
        }
    }
}
