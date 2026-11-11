import Foundation
import Testing
import VoyagerModel
@testable import Domain

/// Swift output must equal what the web's `itineraryLayout.js` produced for the same arguments.
@Suite struct ItineraryLayoutGoldenTests {
    static let cases = ItineraryGoldenCase.all("itineraryLayout")

    static func run(_ c: ItineraryGoldenCase) -> JSONValue? {
        let layout: JSONValue? = c.arg(1)
        switch c.fn {
        case "itineraryFingerprint":
            return .string(ItineraryLayout.fingerprint(c.arg(0)))
        case "activeLayout":
            return ItineraryLayout.activeLayout(c.arg(0), layout) ?? .null
        case "slotRanks":
            return .object(Dictionary(ItineraryLayout.slotRanks(c.arg(0)).map { ($0.key, JSONValue.number($0.rank)) },
                                      uniquingKeysWith: { _, last in last }))
        case "citiesCompatible":
            return .bool(ItineraryLayout.citiesCompatible(c.arg(0), c.arg(1)))
        case "arrangeItinerary":
            let edits: JSONValue = c.args.count > 2 ? c.arg(2) : .object([:])
            return ItineraryLayout.arrange(c.arg(0), layout: layout, edits: edits)
        case "moveTargets":
            return .array(ItineraryLayout.moveTargets(c.arg(0), layout: layout, key: c.arg(2).string ?? ""))
        case "moveSlot":
            return ItineraryLayout.moveSlot(
                c.arg(0), layout: layout, key: c.arg(2).string ?? "", day: c.arg(3).int ?? 0, timeOfDay: c.arg(4).string ?? ""
            )
        case "removeSlot":
            return ItineraryLayout.removeSlot(c.arg(0), layout: layout, key: c.arg(2).string ?? "")
        case "restoreSlot":
            return ItineraryLayout.restoreSlot(c.arg(0), layout: layout, key: c.arg(2).string ?? "")
        case "layoutChangeCount":
            return .number(Double(ItineraryLayout.layoutChangeCount(c.arg(0), layout: layout)))
        case "syncPlannedSlots":
            return ItineraryLayout.syncPlannedSlots(c.arg(0), c.arg(1))
        default:
            return nil
        }
    }

    @Test func test_fixturesAreThere() throws {
        #expect(Self.cases.count == 68)
        #expect(Self.cases.count == (try ItineraryGoldenCase.declaredCaseCount("itineraryLayout")))
        let known = Set(Self.cases.map(\.fn))
        #expect(known.isSuperset(of: [
            "itineraryFingerprint", "activeLayout", "slotRanks", "citiesCompatible", "arrangeItinerary", "moveTargets",
            "moveSlot", "removeSlot", "restoreSlot", "layoutChangeCount", "syncPlannedSlots",
        ]))
    }

    @Test(arguments: ItineraryLayoutGoldenTests.cases)
    func test_matchesWeb(_ c: ItineraryGoldenCase) throws {
        let actual = try #require(Self.run(c), "no Swift port wired for \(c.fn)")
        #expect(actual == c.output, "\(c.testDescription)")
    }

    @Test func test_fingerprintKnownValue() throws {
        let lisbon = try ItineraryGoldenCase.named("itineraryLayout", "fingerprint_lisbon")
        let expected = try #require(lisbon.output.string)
        #expect(ItineraryLayout.fingerprint(lisbon.arg(0)) == expected)
        #expect(expected == "1ujusck")
        // FNV-1a of the empty string is its offset basis.
        #expect(ItineraryLayout.fingerprint(.object([:])) == String(0x811c_9dc5, radix: 36))
    }

    @Test func test_slotKeyAndTimes() {
        #expect(ItineraryLayout.times == ["morning", "afternoon", "evening"])
        #expect(ItineraryLayout.slotKey(day: 3, timeOfDay: "evening") == "3-evening")
    }

    @Test func test_removeThenRestoreReturnsToNoChange() throws {
        let itinerary = try ItineraryGoldenCase.named("itineraryLayout", "arrange_no_layout").arg(0)
        let removed = ItineraryLayout.removeSlot(itinerary, layout: nil, key: "1-afternoon")
        #expect(ItineraryLayout.layoutChangeCount(itinerary, layout: removed) == 1)
        let restored = ItineraryLayout.restoreSlot(itinerary, layout: removed, key: "1-afternoon")
        #expect(ItineraryLayout.layoutChangeCount(itinerary, layout: restored) == 0)
    }
}
