import Foundation
import Testing
import VoyagerModel

@testable import SectionsUI

@MainActor
struct InfoTests {
    @Test func test_staticVisaRendersRequirementOnly() {
        let staticData: JSONValue = [
            "requirement": ["visa_type": "visa-free", "max_stay_days": 90, "requirements": ["Passport valid 6 months"]]
        ]
        #expect(VisaSectionView.blocks(staticData) == ["requirement"])
        let full: JSONValue = [
            "requirement": ["visa_type": "e-visa"],
            "vaccinations": ["required": [], "recommended": ["Hepatitis A"]],
            "customs": ["prohibited_items": ["Drones"]],
        ]
        #expect(VisaSectionView.blocks(full) == ["requirement", "vaccinations", "customs"])
        // Empty AI blocks do not render hollow headings.
        #expect(VisaSectionView.blocks(["requirement": ["visa_type": "e-visa"], "vaccinations": [:], "customs": [:]]) == ["requirement"])
    }

    @Test func test_multiCityEmergencyCities() {
        let multi: JSONValue = [
            "cities": [
                ["city": "Berlin, Germany", "emergency_numbers": ["police": "110"]],
                ["city": "Prague, Czechia", "emergency_numbers": ["police": "158"]],
            ]
        ]
        let entries = EmergencyCards.entries(from: multi)
        #expect(entries.map(\.city) == ["Berlin, Germany", "Prague, Czechia"])
        let single = EmergencyCards.entries(from: ["emergency_numbers": ["police": "110"]])
        #expect(single.count == 1 && single[0].city == nil)
        #expect(EmergencyCards.entries(from: .null).isEmpty)
        #expect(EmergencyOffline.fileName(city: "Berlin, Germany") == "emergency-card-berlin-germany.pdf")
        #expect(EmergencyOffline.fileName(city: nil) == "emergency-card.pdf")
    }

    @Test func test_emergencyOfflinePDFIsWritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("offline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = EmergencyCardEntry(city: nil, data: ["emergency_numbers": ["police": "110", "ambulance": "112"]])
        let files = try #require(EmergencyOffline.save(entries: [entry], into: dir))
        let data = try Data(contentsOf: files[0])
        #expect(data.prefix(4) == Data("%PDF".utf8))
    }

    @Test func test_packingCheckedPersists() {
        let data: JSONValue = [
            "categories": [["name": "Clothes", "items": [["item": "Jacket", "essential": true]]]],
            "luggage_note": "Carry-on only",
            "total_items": 1,
        ]
        let key = PackingState.key(category: "Clothes", item: "Jacket")
        let payload = PackingState.payload(data: data, checked: [key], custom: ["Clothes": ["Umbrella"]])
        #expect(payload["checked_items"][key].bool == true)
        #expect(payload["total_items"].int == 2)
        #expect(payload["checked_count"].int == 1)
        // A saved list reloads its checked and custom items.
        #expect(PackingState.checked(in: payload) == [key])
        #expect(PackingState.custom(in: payload) == ["Clothes": ["Umbrella"]])
        // An unchecked item is dropped, not stored as false.
        let cleared = PackingState.payload(data: data, checked: [], custom: [:])
        #expect(cleared["checked_items"].object?.isEmpty == true)
    }

    @Test func test_confidenceGradeThresholds() {
        #expect(ConfidenceGrade.grade(total: 100) == .green)
        #expect(ConfidenceGrade.grade(total: 71) == .green)
        #expect(ConfidenceGrade.grade(total: 70) == .amber)
        #expect(ConfidenceGrade.grade(total: 41) == .amber)
        #expect(ConfidenceGrade.grade(total: 40) == .red)
        #expect(ConfidenceGrade.grade(total: 0) == .red)
        #expect(ConfidenceGrade.grade(of: ["total": 80, "grade": "red"]) == .green)
        #expect(ConfidenceGrade.grade(of: ["grade": "amber"]) == .amber)
        #expect(ConfidenceHeaderView.family(for: .green) == .green)
    }

    @Test func test_gettingAroundGroupsByScope() {
        let options: [JSONValue] = [
            ["name": "Metro", "scope": "intra_city"], ["name": "Train", "scope": "inter_city"], ["name": "Ferry"],
        ]
        let groups = GettingAroundSectionView.groups(options)
        #expect(groups.map { $0.options.count } == [1, 1, 1])
        #expect(GettingAroundSectionView.groups([]).isEmpty)
    }

    @Test func test_walkingTourImageNeverExceeds120() {
        #expect(WalkingToursSectionView.imageSide <= 120)
    }

    @Test func test_weatherSymbols() {
        #expect(WeatherSymbol.name(code: 0) == "sun.max")
        #expect(WeatherSymbol.name(code: 63) == "cloud.rain")
        #expect(WeatherSymbol.name(code: nil) == "cloud.sun")
    }
}

@MainActor
struct InfoRobustnessTests {
    @Test func test_hugeAndNonFiniteNumbersNeverTrap() {
        #expect(Info.clampedInt(1e30) == 1_000_000_000)
        #expect(Info.clampedInt(-1e30) == -1_000_000_000)
        #expect(Info.clampedInt(.nan) == nil)
        #expect(Info.clampedInt(.infinity) == nil)
        #expect(Info.clampedInt(nil) == nil)
        #expect(Info.clampedInt(89.6) == 90)
        #expect(Info.text(.number(1e30)) != nil)
        #expect(Info.text(.number(.nan)) == nil)
        #expect(Info.text(.number(.infinity)) == nil)
        let packing: JSONValue = ["categories": [], "total_items": .number(1e30)]
        #expect(PackingState.payload(data: packing, checked: [], custom: [:])["total_items"].int == 1_000_000_000)
        let confidence: JSONValue = ["total": .number(1e30)]
        #expect(ConfidenceGrade.grade(of: confidence) == .green)
        // Bodies built from hostile numbers must not crash.
        let weather: JSONValue = ["poor_weather_day_count": .number(1e30), "days": [["temp_high_c": .number(1e30), "temp_low_c": .number(.infinity)]]]
        _ = WeatherSectionView(data: weather, ctx: .inert).body
        _ = VisaSectionView(data: ["requirement": ["max_stay_days": .number(1e30)]], ctx: .inert).body
        _ = ConfidenceHeaderView(data: ["total": .number(1e30), "sub_scores": ["safety": ["score": .number(1e30)]]], ctx: .inert).body
    }

    @Test func test_httpURLsAreRejected() {
        #expect(Info.httpsURL("http://example.com/a") == nil)
        #expect(Info.httpsURL("https://example.com/a") != nil)
        #expect(Info.httpsURL("javascript:alert(1)") == nil)
    }
}
