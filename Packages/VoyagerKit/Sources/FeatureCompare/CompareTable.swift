import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The comparison grid: one row per measure, one column per destination, the best value per row marked.
/// Regular width shows every column; compact width scrolls horizontally with the row header pinned.
struct CompareTable: View {
    let columns: [CompareColumn]
    let best: [String: Set<Int>]
    let onPlan: (Int) -> Void
    let onRetry: (Int) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var scrolled: CGFloat = 0

    static let rowKeys = ["estimate", "flight", "hotel", "weather", "visa", "ease", "safety", "english", "daily"]
    private let labelWidth: CGFloat = 112
    private let compactColumnWidth: CGFloat = 168

    private var regular: Bool { AdaptiveLayout.isRegular(sizeClass) }

    var body: some View {
        if regular {
            grid
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                grid
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self, value: proxy.frame(in: .named("compare.scroll")).minX)
                        })
            }
            .coordinateSpace(name: "compare.scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrolled = max(0, -$0) }
        }
    }

    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.md) {
            GridRow {
                pinned(Color.clear.frame(width: labelWidth, height: 1))
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    header(column, index: index)
                }
            }
            ForEach(Self.rowKeys, id: \.self) { key in
                Divider().gridCellColumns(columns.count + 1)
                GridRow {
                    pinned(
                        Text(verbatim: Self.label(key))
                            .font(VFont.body(.caption, weight: .semibold))
                            .foregroundStyle(SemanticColor.textMuted)
                            .frame(width: labelWidth, alignment: .leading))
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        cell(key, column, isBest: best[key]?.contains(index) == true)
                            .frame(width: regular ? nil : compactColumnWidth, alignment: .topLeading)
                            .frame(maxWidth: regular ? .infinity : nil, alignment: .topLeading)
                    }
                }
            }
            GridRow {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    if column.summary != nil {
                        VButton(L10n.text(K.misc.compare.planThis), tid: "compare.plan.\(index)") { onPlan(index) }
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    /// A row header that stays in view while the columns scroll.
    private func pinned<Content: View>(_ content: Content) -> some View {
        content
            .padding(.trailing, Spacing.xs)
            .background(SemanticColor.surface)
            .offset(x: regular ? 0 : scrolled)
            .zIndex(1)
    }

    private func header(_ column: CompareColumn, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: column.summary?.label ?? column.destination)
                .font(VFont.body(.headline, weight: .bold))
                .foregroundStyle(SemanticColor.text)
            if case .failed(let message) = column.status {
                Text(verbatim: L10n.text(K.misc.compare.couldntLoad))
                    .font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.destructive)
                Text(verbatim: message)
                    .font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.textMuted)
                VButton(L10n.text(K.misc.compare.retry), tid: "compare.retry.\(index)", role: .secondary) { onRetry(index) }
            }
            if let missing = column.summary?.missing, !missing.isEmpty {
                Text(verbatim: L10n.text(K.misc.compare.missing, ["list": missing.joined(separator: ", ")]))
                    .font(VFont.body(.caption))
                    .foregroundStyle(Palette.color(.amber, .s700))
            }
        }
        .frame(width: regular ? nil : compactColumnWidth, alignment: .topLeading)
        .frame(maxWidth: regular ? .infinity : nil, alignment: .topLeading)
    }

    @ViewBuilder private func cell(_ key: String, _ column: CompareColumn, isBest: Bool) -> some View {
        switch column.status {
        case .loading:
            Skeleton(lines: 1)
        case .failed:
            Text(verbatim: "—").foregroundStyle(SemanticColor.textMuted)
        case .done(let summary):
            if let content = Self.content(key, summary) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    content
                    if isBest { Pill(text: L10n.text(K.misc.compare.best), tone: .good) }
                }
            } else {
                Text(verbatim: "—").foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    // MARK: - Row content

    static func label(_ key: String) -> String {
        switch key {
        case "estimate": L10n.text(K.misc.compare.row.estimate)
        case "flight": L10n.text(K.misc.compare.row.flight)
        case "hotel": L10n.text(K.misc.compare.row.hotel)
        case "weather": L10n.text(K.misc.compare.row.weather)
        case "visa": L10n.text(K.misc.compare.row.visa)
        case "ease": L10n.text(K.misc.compare.row.ease)
        case "safety": L10n.text(K.misc.compare.row.safety)
        case "english": L10n.text(K.misc.compare.row.english)
        default: L10n.text(K.misc.compare.row.daily)
        }
    }

    private static func usd(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return Fmt.currency(value, code: "USD")
    }

    private static func strong(_ text: String) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.subheadline, weight: .semibold))
            .foregroundStyle(SemanticColor.text)
    }

    private static func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.caption))
            .foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The cell for `key`, or nil when the summary has nothing for it (shown as a dash).
    static func content(_ key: String, _ summary: CompareSummary) -> AnyView? {
        switch key {
        case "estimate": estimateCell(summary.estimate)
        case "flight": flightCell(summary.flight)
        case "hotel": hotelCell(summary.hotel)
        case "weather": weatherCell(summary.weather)
        case "visa": visaCell(summary.visa)
        case "ease": easeCell(summary.ease)
        case "safety": summary.ease?.safety.map { AnyView(strong("\($0)/20")) }
        case "english": summary.ease?.english.map { AnyView(strong("\($0)/20")) }
        default: summary.dailyCostUsd.map { AnyView(strong(L10n.text(K.misc.compare.perDay, ["amount": usd($0)]))) }
        }
    }

    private static func estimateCell(_ estimate: CompareEstimate?) -> AnyView? {
        guard let estimate, let total = estimate.totalUsd else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.xs) {
                strong(usd(total))
                Pill(text: L10n.text(K.misc.compare.estimate), tone: .neutral)
                if estimate.budgetStatus == "under" { Pill(text: L10n.text(K.misc.compare.underBudget), tone: .good) }
                if estimate.budgetStatus == "over" { Pill(text: L10n.text(K.misc.compare.overBudget), tone: .bad) }
                if estimate.partial == true { note(L10n.text(K.misc.compare.partial)) }
            })
    }

    private static func flightCell(_ flight: CompareFlight?) -> AnyView? {
        guard let flight else { return nil }
        var parts: [String] = []
        if let stops = flight.stops {
            parts.append(stops == 0 ? L10n.text(K.misc.compare.nonstop) : L10n.text(K.misc.compare.stops, count: stops))
        }
        let duration = CompareRules.durationText(minutes: flight.durationMinutes.map(Double.init)) { hours, minutes in
            L10n.text(K.misc.compare.duration, ["h": String(hours), "m": String(minutes)])
        }
        if let duration { parts.append(duration) }
        if let airline = flight.airline, !airline.isEmpty { parts.append(airline) }
        let details = parts.joined(separator: " · ")
        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.xs) {
                strong(usd(flight.priceUsd))
                if flight.source == "estimate" { Pill(text: L10n.text(K.misc.compare.estimate), tone: .warn) }
                if !details.isEmpty { note(details) }
            })
    }

    private static func hotelCell(_ hotel: CompareHotel?) -> AnyView? {
        guard let hotel else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.xs) {
                strong(usd(hotel.typicalNightlyUsd) + " " + L10n.text(K.misc.compare.typical))
                if let cheapest = hotel.cheapestGoodNightlyUsd {
                    note(L10n.text(K.misc.compare.fromWellReviewed, ["amount": usd(cheapest)]))
                }
            })
    }

    private static func weatherCell(_ weather: CompareWeather?) -> AnyView? {
        guard let weather else { return nil }
        let high = weather.avgHighC.map { "\(Int($0.rounded()))°" } ?? "—"
        let low = weather.avgLowC.map { "\(Int($0.rounded()))°" } ?? "—"
        let unit = weather.avgHighC != nil || weather.avgLowC != nil ? "C" : ""
        let poor = weather.poorDays.map(String.init)
        let total = weather.totalDays.map(String.init)
        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.xs) {
                strong("\(high) / \(low)\(unit)")
                if weather.source != "open-meteo" { Pill(text: L10n.text(K.misc.compare.climateEstimate), tone: .warn) }
                if let poor, let total { note(L10n.text(K.misc.compare.daysPoor, ["poor": poor, "total": total])) }
            })
    }

    private static func visaCell(_ visa: CompareVisa?) -> AnyView? {
        guard let visa else { return nil }
        var parts: [String] = []
        if let fee = visa.feeUsd {
            parts.append(fee == 0 ? L10n.text(K.misc.compare.noFee) : L10n.text(K.misc.compare.fee, ["amount": usd(fee)]))
        }
        if let stay = visa.maxStayDays { parts.append(L10n.text(K.misc.compare.maxStay, count: stay)) }
        let details = parts.joined(separator: " · ")
        let verified = visa.verified == true
        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.xs) {
                strong(visa.visaType ?? "—")
                Pill(
                    text: L10n.text(verified ? K.misc.compare.verified : K.misc.compare.aiCheck),
                    tone: verified ? .good : .warn)
                if !details.isEmpty { note(details) }
            })
    }

    private static func easeCell(_ ease: CompareEase?) -> AnyView? {
        guard let total = ease?.total else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.xs) {
                strong("\(total)/100")
                if let grade = ease?.grade, let pill = gradePill(grade) { pill }
            })
    }

    private static func gradePill(_ grade: String) -> Pill? {
        switch grade {
        case "green": Pill(text: L10n.text(K.misc.compare.grade.green), tone: .good)
        case "amber": Pill(text: L10n.text(K.misc.compare.grade.amber), tone: .warn)
        case "red": Pill(text: L10n.text(K.misc.compare.grade.red), tone: .bad)
        default: nil
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A small coloured tag (Best, Estimate, Verified, grade).
struct Pill: View {
    enum Tone { case neutral, good, warn, bad }
    let text: String
    let tone: Tone

    var body: some View {
        Text(verbatim: text)
            .font(VFont.body(.caption2, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Palette.color(.slate, .s600)
        case .good: Palette.color(.emerald, .s700)
        case .warn: Palette.color(.amber, .s700)
        case .bad: Palette.color(.red, .s700)
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: Palette.color(.slate, .s100)
        case .good: Palette.color(.emerald, .s100)
        case .warn: Palette.color(.amber, .s100)
        case .bad: Palette.color(.red, .s100)
        }
    }
}
