import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

@MainActor
@Suite(.serialized)
struct PaletteTests {
    /// The catalog colour by asset name in a given appearance (what `Palette.color` points at).
    private static let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    private static let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

    private func resolve(_ family: Family, _ stop: Stop, _ style: UIUserInterfaceStyle) -> [CGFloat]? {
        let name = "\(family.rawValue)-\(stop.rawValue)"
        let traits = style == .dark ? Self.darkTraits : Self.lightTraits
        guard let named = UIColor(named: name, in: Bundle.module, compatibleWith: traits) else { return nil }
        let color = named.resolvedColor(with: traits)
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    @Test func test_familyAndStopCounts() {
        #expect(Family.allCases.count == 22)
        #expect(Stop.allCases.count == 11)
    }

    /// The committed catalog source, read without CoreUI. The first `UIColor(named:in:)` of the process stalled
    /// intermittently on CI (always the first case, `.gray`; nothing else running; 240 s limit), so the exhaustive
    /// sweep checks each colorset's Contents.json (light + dark entries, alpha 1) and only the few tests below touch
    /// the compiled catalog, behind a 1-minute guard so a stall fails fast.
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

    @Test(.timeLimit(.minutes(1)), arguments: Family.allCases)
    func test_everyFamilyStopResolves(family: Family) throws {
        for stop in Stop.allCases {
            _ = Palette.color(family, stop)
            let found = try sourceAppearances(family, stop)
            #expect(found.light, "\(family)-\(stop.rawValue) light missing")
            #expect(found.dark, "\(family)-\(stop.rawValue) dark missing")
            #expect(found.alphaOne, "\(family)-\(stop.rawValue) alpha != 1")
        }
    }

    /// Compiled catalog: every family's 600 stop resolves in light and dark (one lookup per family and theme).
    @Test(.timeLimit(.minutes(1)))
    func test_compiledCatalogResolvesInBothThemes() {
        for family in Family.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let components = resolve(family, .s600, style)
                #expect(components != nil, "\(family)-600 \(style.rawValue) missing from compiled catalog")
                #expect(components?[3] == 1)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func test_teal600DiffersBetweenThemes() {
        #expect(resolve(.teal, .s600, .light) != resolve(.teal, .s600, .dark))
    }

    @Test(.timeLimit(.minutes(1)))
    func test_teal600LightIsTokenValue() throws {
        let light = try #require(resolve(.teal, .s600, .light))
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
