import Foundation
import L10n
import VoyagerModel

/// The line under the chart: typical range, lowest and target, each from a catalogue template (the range's colon and
/// dash are the template's, not literals).
enum PriceStoryLegend {
    static func parts(_ story: PriceStory) -> [String] {
        let code = story.currency ?? "USD"
        var parts: [String] = []
        if let typical = story.typical {
            parts.append(
                L10n.text(
                    K.priceStory.chart.typicalRange,
                    ["low": Fmt.currency(typical.low, code: code), "high": Fmt.currency(typical.high, code: code)]))
        }
        if let lowest = story.lowest {
            parts.append(L10n.text(K.priceStory.chart.lowest, ["price": Fmt.currency(lowest.price, code: code)]))
        }
        if let target = story.target {
            parts.append(L10n.text(K.priceStory.chart.target, ["price": Fmt.currency(target, code: code)]))
        }
        return parts
    }

    static func text(_ story: PriceStory) -> String { parts(story).joined(separator: " · ") }
}
