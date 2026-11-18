import SwiftUI
import Testing

@testable import DesignSystem

@MainActor
@Suite(.serialized)
struct PaletteTests {
    @Test func test_familyAndStopCounts() {
        #expect(Family.allCases.count == 22)
        #expect(Stop.allCases.count == 11)
    }

    /// The committed catalog source, read without CoreUI. The first `UIColor(named:in:)` of the process stalled
    /// intermittently on CI (always the first case, `.gray`; nothing else running; 240 s limit), so the exhaustive
    /// sweep checks each colorset's Contents.json (light + dark entries, alpha 1); no unit test resolves through
    /// CoreUI (see test_compiledCatalogShipsInBundle).
    private func sourceAppearances(_ family: Family, _ stop: Stop) throws -> (light: Bool, dark: Bool, alphaOne: Bool) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DesignSystem/Resources/Colors.xcassets")
        let url = root.appendingPathComponent("\(family.rawValue)-\(stop.rawValue).colorset/Contents.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        var (light, dark, alphaOne) = (false, false, true)
        for entry in (json?["colors"] as? [[String: Any]]) ?? [] {
            let values = ((entry["appearances"] as? [[String: String]]) ?? []).compactMap { $0["value"] }
            if values.contains("dark") { dark = true } else if values.isEmpty { light = true }
            let comps = (entry["color"] as? [String: Any])?["components"] as? [String: Any]
            if let alpha = comps?["alpha"] as? String, Double(alpha) != 1 { alphaOne = false }
        }
        return (light, dark, alphaOne)
    }

    @Test(arguments: Family.allCases)
    func test_everyFamilyStopResolves(family: Family) throws {
        for stop in Stop.allCases {
            _ = Palette.color(family, stop)
            let found = try sourceAppearances(family, stop)
            #expect(found.light, "\(family)-\(stop.rawValue) light missing")
            #expect(found.dark, "\(family)-\(stop.rawValue) dark missing")
            #expect(found.alphaOne, "\(family)-\(stop.rawValue) alpha != 1")
        }
    }

    /// Light (default) and dark sRGB components from a colorset's Contents.json. No CoreUI.
    private func sourceComponents(_ family: Family, _ stop: Stop) throws -> (light: [Double], dark: [Double]) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DesignSystem/Resources/Colors.xcassets")
        let url = root.appendingPathComponent("\(family.rawValue)-\(stop.rawValue).colorset/Contents.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        var out: (light: [Double], dark: [Double]) = ([], [])
        for entry in (json?["colors"] as? [[String: Any]]) ?? [] {
            let isDark = ((entry["appearances"] as? [[String: String]]) ?? []).contains { $0["value"] == "dark" }
            let comps = (entry["color"] as? [String: Any])?["components"] as? [String: String] ?? [:]
            let rgb = ["red", "green", "blue"].compactMap { comps[$0].flatMap(Double.init) }
            if isDark { out.dark = rgb } else { out.light = rgb }
        }
        return out
    }

    /// The compiled catalog ships in the module bundle. Only its presence is checked: the first CoreUI lookup
    /// (`UIColor(named:in:compatibleWith:)`) stalls for minutes on CI's headless xctest host (runs 43743211219,
    /// 43711512195, 44185823536: every compiled-lookup test hit its guard, three retries in a row, while passing
    /// runs take well under a second), so no unit test resolves through CoreUI. The real resolution is exercised by
    /// the app in ui-smoke.
    @Test func test_compiledCatalogShipsInBundle() {
        let car = Bundle.module.url(forResource: "Assets", withExtension: "car")
        #expect(car != nil, "Assets.car missing from the DesignSystem resource bundle")
    }

    @Test func test_teal600DiffersBetweenThemes() throws {
        let c = try sourceComponents(.teal, .s600)
        #expect(c.light != c.dark)
    }

    @Test func test_teal600LightIsTokenValue() throws {
        let light = try sourceComponents(.teal, .s600).light
        #expect(light.count == 3)
        #expect(abs(light[0] - 0.051) < 0.002)
        #expect(abs(light[1] - 0.580) < 0.002)
        #expect(abs(light[2] - 0.533) < 0.002)
    }

    @Test func test_sectionAccentFamilies() {
        #expect(SectionAccent.family(for: "nope") == .primary)
        #expect(SectionAccent.family(for: "flights") == .sky)
        #expect(SectionAccent.family(for: "weather") == .sky)
        #expect(SectionAccent.family(for: "emergency_card") == .red)
    }
}
