import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

@MainActor
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

    /// One case per family so each stays far inside Swift Testing's per-test time limit.
    @Test(arguments: Family.allCases)
    func test_everyFamilyStopResolves(family: Family) {
        for stop in Stop.allCases {
            _ = Palette.color(family, stop)
            for style in [UIUserInterfaceStyle.light, .dark] {
                let components = resolve(family, stop, style)
                #expect(components != nil, "\(family)-\(stop.rawValue) \(style.rawValue) missing")
                #expect(components?[3] == 1)
            }
        }
    }

    @Test func test_teal600DiffersBetweenThemes() {
        #expect(resolve(.teal, .s600, .light) != resolve(.teal, .s600, .dark))
    }

    @Test func test_teal600LightIsTokenValue() throws {
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
