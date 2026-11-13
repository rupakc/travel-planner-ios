import Charts
import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// Daily users, sessions and events as line charts, plus the top events and screens.
struct AnalyticsView: View {
    let model: AnalyticsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch model.phase {
                case .idle, .loading:
                    Text(verbatim: L10n.text(K.adminTelemetry.loading)).foregroundStyle(SemanticColor.textMuted)
                case .failed:
                    EmptyState(icon: "exclamationmark.triangle", title: L10n.text(K.adminTelemetry.error))
                case .unavailable:
                    EmptyState(icon: "chart.xyaxis.line", title: L10n.text(K.adminTelemetry.empty))
                case .loaded:
                    if model.isEmpty {
                        EmptyState(icon: "chart.xyaxis.line", title: L10n.text(K.adminTelemetry.empty))
                    } else {
                        loaded
                    }
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .refreshable { await model.load() }
        .task { if model.phase == .idle || model.phase == .failed { await model.load() } }
        .accessibilityIdentifier("admin.analytics")
    }

    @ViewBuilder private var loaded: some View {
        let tiles = [
            (L10n.text(K.adminTelemetry.usersToday), model.usersToday),
            (L10n.text(K.adminTelemetry.sessionsToday), model.sessionsToday),
            (L10n.text(K.adminTelemetry.users7d), model.summary.users7d ?? 0),
            (L10n.text(K.adminTelemetry.userDays7), model.userDays7),
        ]
        StatTiles(tiles: tiles)
        DailyChart(title: L10n.text(K.adminTelemetry.chartTitle), points: model.users)
        DailyChart(title: L10n.text(K.mobile.admin.chartSessions), points: model.sessions)
        DailyChart(title: L10n.text(K.mobile.admin.chartEvents), points: model.events)
        if !model.topEvents.isEmpty {
            ranked(
                title: L10n.text(K.adminTelemetry.topEvents),
                head: (L10n.text(K.adminTelemetry.colEvent), L10n.text(K.adminTelemetry.colEvents)),
                rows: model.topEvents.map { ($0.event ?? "", $0.events ?? 0) })
        }
        if !model.topScreens.isEmpty {
            ranked(
                title: L10n.text(K.adminTelemetry.topScreens),
                head: (L10n.text(K.adminTelemetry.colScreen), L10n.text(K.adminTelemetry.colViews)),
                rows: model.topScreens.map { ($0.route ?? "", $0.views ?? 0) })
        }
    }

    private func ranked(title: String, head: (String, String), rows: [(String, Int)]) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: title).font(VFont.body(.headline)).foregroundStyle(SemanticColor.text)
                HStack {
                    Text(verbatim: head.0)
                    Spacer(minLength: Spacing.sm)
                    Text(verbatim: head.1)
                }
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: row.0).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.text)
                        Spacer(minLength: Spacing.sm)
                        Text(verbatim: Fmt.number(Double(row.1), fractionDigits: 0))
                            .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.text)
                    }
                }
            }
        }
    }
}

/// Four number tiles, two per row (a plain stack so hosted snapshots lay it out).
struct StatTiles: View {
    let tiles: [(String, Int)]

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(0..<(tiles.count + 1) / 2, id: \.self) { row in
                HStack(spacing: Spacing.sm) {
                    let slice = Array(tiles[(row * 2)..<min(row * 2 + 2, tiles.count)])
                    ForEach(Array(slice.enumerated()), id: \.offset) { _, tile in
                        VCard {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(verbatim: tile.0).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                                Text(verbatim: Fmt.number(Double(tile.1), fractionDigits: 0))
                                    .font(VFont.display(.title2)).foregroundStyle(SemanticColor.text)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A line chart of one daily series, with a spoken summary.
struct DailyChart: View {
    let title: String
    let points: [DailyPoint]

    private var summary: String {
        guard let first = points.first, let last = points.last, let peak = points.max(by: { $0.value < $1.value }) else {
            return title
        }
        let style = Date.FormatStyle(
            date: .abbreviated, time: .omitted, locale: LanguageController.current.intlLocale,
            timeZone: TimeZone(identifier: "UTC") ?? .gmt)
        return L10n.text(
            K.adminTelemetry.chartSummary,
            [
                "from": first.date.formatted(style), "to": last.date.formatted(style), "max": Fmt.number(Double(peak.value), fractionDigits: 0),
                "peak": peak.date.formatted(style),
            ])
    }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: title).font(VFont.body(.headline)).foregroundStyle(SemanticColor.text)
                Chart(points) { point in
                    LineMark(x: .value("day", point.date, unit: .day), y: .value("count", point.value))
                        .foregroundStyle(SemanticColor.primary)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...max(1, points.map(\.value).max() ?? 1))
                .frame(height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
            }
        }
    }
}
