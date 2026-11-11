import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

struct PaletteTests {
    /// The catalog colour by asset name in a given appearance (what `Palette.color` points at).
    private func resolve(_ family: Family, _ stop: Stop, _ style: UIUserInterfaceStyle) -> [CGFloat]? {
        let name = "\(family.rawValue)-\(stop.rawValue)"
        let traits = UITraitCollection(userInterfaceStyle: style)
        guard let color = UIColor(named: name, in: Bundle.module, compatibleWith: traits) else { return nil }
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    @Test func test_everyFamilyStopResolves() {
        #expect(Family.allCases.count == 22)
        #expect(Stop.allCases.count == 11)
        for family in Family.allCases {
            for stop in Stop.allCases {
                _ = Palette.color(family, stop)
                for style in [UIUserInterfaceStyle.light, .dark] {
                    let components = resolve(family, stop, style)
                    #expect(components != nil, "\(family)-\(stop.rawValue) \(style.rawValue) missing")
                    #expect(components?[3] == 1)
                }
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
