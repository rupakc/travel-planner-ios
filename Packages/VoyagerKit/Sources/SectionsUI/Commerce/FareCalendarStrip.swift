import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The cheapest live fare for departure dates around the searched one (`/api/flights/fare-calendar`). Loaded when
/// shown; `503` (no live prices on this server) calls `onUnavailable` so the host hides the whole control.
struct FareCalendarStrip: View {
    let load: @MainActor @Sendable () async -> SectionRemote
    let onUnavailable: () -> Void

    enum Phase: Equatable {
        case loading, loaded([JSONValue]), failed(String?)
    }

    @State private var phase: Phase
    @State private var attempt = 0

    init(load: @escaping @MainActor @Sendable () async -> SectionRemote, onUnavailable: @escaping () -> Void, initial: Phase = .loading) {
        self.load = load
        self.onUnavailable = onUnavailable
        _phase = State(initialValue: initial)
    }

    static func dates(in data: JSONValue) -> [JSONValue] { data["dates"].array ?? [] }

    /// `"Tue"` and `"Apr 7"` for an ISO date, in the app language and UTC (the date has no time zone).
    static func dayParts(_ iso: String?) -> (weekday: String, date: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let iso, let date = formatter.date(from: iso) else { return ("", iso ?? "") }
        let weekday = DateFormatter()
        weekday.locale = LanguageController.current.intlLocale
        weekday.timeZone = TimeZone(identifier: "UTC")
        weekday.setLocalizedDateFormatFromTemplate("EEE")
        let day = DateFormatter()
        day.locale = weekday.locale
        day.timeZone = weekday.timeZone
        day.setLocalizedDateFormatFromTemplate("MMMd")
        return (weekday.string(from: date), day.string(from: date))
    }

    static func deltaText(_ delta: Double?) -> String {
        guard let delta, delta.isFinite else { return "" }
        if abs(delta) < 0.5 { return L10n.text(K.alerts.fare.same) }
        let amount = Fmt.currency(abs(delta), code: "USD")
        return (delta < 0 ? "−" : "+") + amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.alerts.fare.section))
                .font(VFont.body(.footnote, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
            Text(verbatim: L10n.text(K.alerts.fare.hint))
                .font(VFont.body(.caption))
                .foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            switch phase {
            case .loading:
                Skeleton(lines: 2)
            case .failed(let detail):
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: detail ?? L10n.text(K.alerts.fare.error))
                        .font(VFont.body(.caption))
                        .foregroundStyle(Palette.color(.amber, .s700))
                        .fixedSize(horizontal: false, vertical: true)
                    VButton(L10n.text(K.alerts.ui.retry), tid: "fare-calendar.retry", role: .secondary) {
                        phase = .loading
                        attempt += 1
                    }
                }
            case .loaded(let dates):
                if dates.isEmpty {
                    Text(verbatim: L10n.text(K.alerts.fare.none)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                } else {
                    strip(dates)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SemanticColor.surface, in: RoundedRectangle(cornerRadius: Radius.itemCard))
        .overlay { RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .task(id: attempt) { await fetch() }
    }

    private func fetch() async {
        switch await load() {
        case .loaded(let data): phase = .loaded(Self.dates(in: data))
        case .unavailable: onUnavailable()
        case .failed(let detail): phase = .failed(detail)
        }
    }

    private func strip(_ dates: [JSONValue]) -> some View {
        let selected = dates.first { $0["is_selected"].bool == true } ?? .null
        let cheapest = FareCalendar.cheapestDeparture(dates)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(Array(dates.enumerated()), id: \.offset) { _, entry in
                    cell(entry, selected: selected, isCheapest: entry["departure_date"].string == cheapest)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func cell(_ entry: JSONValue, selected: JSONValue, isCheapest: Bool) -> some View {
        let isSelected = entry["is_selected"].bool == true
        let parts = Self.dayParts(entry["departure_date"].string)
        let price = entry["cheapest_usd"].double.map { Fmt.currency($0, code: "USD") } ?? "—"
        let delta = isSelected ? L10n.text(K.alerts.fare.yours) : Self.deltaText(FareCalendar.fareDelta(entry, selected))
        let family: Family = isCheapest ? .emerald : .gray
        return VStack(spacing: 2) {
            Text(verbatim: parts.weekday).font(VFont.body(.caption2)).foregroundStyle(SemanticColor.textMuted)
            Text(verbatim: parts.date).font(VFont.body(.caption, weight: .medium)).foregroundStyle(SemanticColor.text)
            Text(verbatim: price).font(VFont.body(.footnote, weight: .bold)).foregroundStyle(Palette.color(family, .s700))
            Text(verbatim: delta).font(VFont.body(.caption2)).foregroundStyle(SemanticColor.textMuted).frame(minHeight: 14)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .frame(minWidth: 64)
        .background(
            isCheapest ? Palette.color(.emerald, .s50) : SemanticColor.surfaceRaised,
            in: RoundedRectangle(cornerRadius: Radius.input))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.input)
                .strokeBorder(isSelected ? SemanticColor.primary : (isCheapest ? Palette.color(.emerald, .s200) : SemanticColor.border),
                              lineWidth: isSelected ? 2 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fare-calendar.cell")
    }
}
