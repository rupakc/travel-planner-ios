import Accessibility
import Charts
import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// What the chart draws, from the story's observed `points` only. An estimate is never a point, and nothing is
/// computed here beyond parsing dates and padding the y range: the typical band and target are the server's.
struct StoryChartData: Equatable {
    struct Plotted: Identifiable, Equatable {
        let index: Int
        let point: PricePoint
        let date: Date
        var id: Int { index }
    }

    let points: [Plotted]
    let typical: TypicalRange?
    let target: Double?
    let currency: String

    init(story: PriceStory) {
        var plotted: [Plotted] = []
        for (index, point) in story.points.enumerated() {
            guard let date = Self.parse(point.at) else { continue }
            plotted.append(Plotted(index: index, point: point, date: date))
        }
        points = plotted
        typical = story.typical
        target = story.target
        currency = story.currency ?? "USD"
    }

    /// A line needs two checks; with fewer the card says how many there are instead.
    var showsChart: Bool { points.count >= 2 }

    /// Padded y range holding every price, the typical band and the target.
    var yDomain: ClosedRange<Double> {
        var values = points.map(\.point.price)
        if let typical { values += [typical.low, typical.high] }
        if let target { values.append(target) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max((high - low) * 0.12, high * 0.02, 1)
        return (low - pad)...(high + pad)
    }

    static func parse(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// VoiceOver's view of the chart: one numbered data point per check, so it can be stepped through and played as audio.
struct StoryChartDescriptor: AXChartDescriptorRepresentable {
    let data: StoryChartData

    func makeChartDescriptor() -> AXChartDescriptor { Self.descriptor(for: data) }

    static func summary(for data: StoryChartData) -> String {
        guard let first = data.points.first, let last = data.points.last else {
            return L10n.text(K.priceStory.chart.none)
        }
        return L10n.text(
            K.priceStory.chart.label,
            ["n": String(data.points.count), "from": Fmt.date(first.date), "to": Fmt.date(last.date)])
    }

    static func descriptor(for data: StoryChartData) -> AXChartDescriptor {
        let prices = data.points.map(\.point.price)
        let low = prices.min() ?? 0
        let high = max(prices.max() ?? 1, low + 1)
        let count = max(data.points.count, 2)
        let xAxis = AXNumericDataAxisDescriptor(
            title: L10n.text(K.priceStory.title), range: 1...Double(count), gridlinePositions: []
        ) { String(Int($0)) }
        let yAxis = AXNumericDataAxisDescriptor(
            title: data.currency, range: low...high, gridlinePositions: []
        ) { Fmt.currency($0, code: data.currency) }
        let series = AXDataSeriesDescriptor(
            name: L10n.text(K.priceStory.title), isContinuous: true,
            dataPoints: data.points.enumerated().map { offset, plotted in
                AXDataPoint(
                    x: Double(offset + 1), y: plotted.point.price,
                    label: L10n.text(
                        K.priceStory.chart.point,
                        ["price": Fmt.currency(plotted.point.price, code: data.currency), "date": Fmt.date(plotted.date)]))
            })
        return AXChartDescriptor(
            title: L10n.text(K.priceStory.title), summary: summary(for: data), xAxis: xAxis, yAxis: yAxis,
            additionalAxes: [], series: [series])
    }
}

/// The price history: a line through the observed checks, the usual range as a soft band, the target as a dashed
/// rule, the latest check emphasised. Dragging a finger reads off the nearest check.
struct StoryChart: View {
    let data: StoryChartData
    var selected: PricePoint?
    var onScrub: (Date?) -> Void = { _ in }
    @State private var scrubDate: Date?

    private var selectedDate: Date? {
        selected.flatMap { point in data.points.first { $0.point == point }?.date }
    }

    var body: some View {
        Chart {
            if let typical = data.typical, let first = data.points.first, let last = data.points.last {
                RectangleMark(
                    xStart: .value("from", first.date), xEnd: .value("to", last.date),
                    yStart: .value("low", typical.low), yEnd: .value("high", typical.high)
                )
                .foregroundStyle(SemanticColor.primary.opacity(0.14))
            }
            if let target = data.target {
                RuleMark(y: .value("target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Palette.color(.amber, .s600))
            }
            ForEach(data.points) { plotted in
                LineMark(x: .value("date", plotted.date), y: .value("price", plotted.point.price))
                    .foregroundStyle(SemanticColor.primary)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("date", plotted.date), y: .value("price", plotted.point.price))
                    .foregroundStyle(SemanticColor.primary)
                    .symbolSize(plotted.index == data.points.last?.index ? 70 : 24)
            }
            if let selectedDate {
                RuleMark(x: .value("selected", selectedDate))
                    .foregroundStyle(SemanticColor.textMuted.opacity(0.6))
            }
        }
        .chartYScale(domain: data.yDomain)
        .chartXSelection(value: $scrubDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 2)) { value in
                AxisGridLine().foregroundStyle(SemanticColor.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(verbatim: Fmt.shortDate(date)).font(VFont.body(.caption2)).foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(SemanticColor.border)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(verbatim: Fmt.number(number, fractionDigits: 0))
                            .font(VFont.body(.caption2)).foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
        }
        .frame(height: 150)
        .onChange(of: scrubDate) { _, date in onScrub(date) }
        .accessibilityChartDescriptor(StoryChartDescriptor(data: data))
        .accessibilityHint(L10n.text(K.priceStory.chart.help))
    }
}
