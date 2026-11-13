import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// One watched price: title, status chip, price with change since the baseline, lowest seen, when it was last
/// checked, the alert rule, and the actions (check now, live search, edit, pause / resume, delete).
struct WatchCard: View {
    let row: WatchRow
    var busy: AlertsModel.Busy?
    var highlighted = false
    var now = Date()
    var onCheck: () -> Void = {}
    var onLive: () -> Void = {}
    var onEdit: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                priceBlock
                details
                actions
            }
        }
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.primary, lineWidth: 2)
            }
        }
        .opacity(row.isPast ? 0.8 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.watch.\(row.id)")
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(verbatim: row.title)
                    .font(VFont.display(.headline))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                statusChip
            }
            if let subtitle = subtitleText {
                Text(verbatim: subtitle)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: ruleText)
                .font(VFont.body(.caption))
                .foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusChip: some View {
        let family: Family = row.isPast ? .slate : row.isErrored ? .amber : row.isPaused ? .slate : .emerald
        return Text(verbatim: statusText)
            .font(VFont.body(.caption, weight: .medium))
            .foregroundStyle(Palette.color(family, .s800))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Palette.color(family, .s100), in: Capsule())
    }

    @ViewBuilder private var priceBlock: some View {
        if let price = row.price ?? row.baseline {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                PriceText(amount: price, currency: row.currency, estimate: row.isEstimate)
                if let change = changeText {
                    Text(verbatim: change.text)
                        .font(VFont.body(.caption, weight: .medium))
                        .foregroundStyle(change.family.map { Palette.color($0, .s700) } ?? SemanticColor.textMuted)
                }
            }
        } else {
            Text(verbatim: noPriceText)
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.textMuted)
        }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let lowest = row.lowest {
                Text(verbatim: "\(L10n.text(K.alerts.card.lowestSeen)): \(Fmt.currency(lowest, code: row.currency))")
            }
            if let checked = row.checkedAt {
                Text(verbatim: L10n.text(K.alerts.card.checked, ["when": Fmt.relative(checked.timeIntervalSince(now))]))
            }
            if let next = row.nextCheckAt, !row.isPast, !row.isPaused {
                Text(verbatim: L10n.text(K.alerts.card.nextCheck, ["when": Fmt.relative(next.timeIntervalSince(now))]))
            }
            if row.isErrored {
                Text(verbatim: L10n.text(row.kind == .flight ? K.alerts.card.errorFare : K.alerts.card.errorPrice))
                    .foregroundStyle(Palette.color(.amber, .s700))
            }
        }
        .font(VFont.body(.caption))
        .foregroundStyle(SemanticColor.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        let working = busy != nil
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                VButton(
                    busy == .check ? L10n.text(K.alerts.ui.checking) : L10n.text(K.alerts.ui.checkNow),
                    tid: "alerts.check-now", role: .secondary, systemImage: "arrow.clockwise", action: onCheck
                )
                .disabled(working || row.isPast)
                VButton(
                    L10n.text(K.alerts.live.searchNow), tid: "alerts.live-check", role: .secondary,
                    systemImage: "globe", action: onLive
                )
                .disabled(working || row.isPast)
            }
            HStack(spacing: Spacing.sm) {
                VButton(L10n.text(K.alerts.ui.edit), tid: "alerts.edit", role: .tonal, systemImage: "pencil", action: onEdit)
                    .disabled(working || row.isPast)
                if !row.isPast {
                    VButton(
                        row.isPaused || row.isErrored ? L10n.text(K.alerts.ui.resume) : L10n.text(K.alerts.ui.pause),
                        tid: row.isPaused || row.isErrored ? "alerts.resume" : "alerts.pause", role: .tonal,
                        systemImage: row.isPaused || row.isErrored ? "play.fill" : "pause.fill", action: onTogglePause
                    )
                    .disabled(working)
                }
                VButton(
                    L10n.text(K.alerts.ui.delete), tid: "alerts.delete", role: .destructive, systemImage: "trash",
                    action: onDelete
                )
                .disabled(working)
                .accessibilityLabel(L10n.text(K.alerts.card.deleteAria, ["name": row.title]))
            }
            if let link = row.link {
                BookingLink(url: link, section: row.kind == .flight ? "flights" : "\(row.kind.rawValue)s", tid: "alerts.book")
            }
        }
    }

    // MARK: Text

    private var statusText: String {
        if row.isPast { return L10n.text(K.alerts.status.expired) }
        if row.isErrored { return L10n.text(K.alerts.status.problem) }
        if row.isPaused { return L10n.text(K.alerts.status.paused) }
        if row.isPending { return L10n.text(K.alerts.status.pending) }
        if let price = row.price, let baseline = row.baseline, price < baseline - 0.005 {
            return L10n.text(K.alerts.status.dropped)
        }
        return L10n.text(K.alerts.status.watching)
    }

    private var subtitleText: String? {
        if let subtitle = row.subtitle, !subtitle.isEmpty { return subtitle }
        guard let start = row.startDay else { return nil }
        var parts = [dayRange(start, row.endDay)]
        if row.endDay == nil { parts[0] += " " + L10n.text(K.alerts.card.oneWay) }
        if let travellers = row.travellers {
            parts.append(L10n.text(K.alerts.travellers, count: travellers))
        }
        if row.flexible { parts.append(L10n.text(K.alerts.card.flexDays)) }
        return parts.joined(separator: " · ")
    }

    private func dayRange(_ start: Date, _ end: Date?) -> String {
        var format = Date.FormatStyle().month(.abbreviated).day()
        format.locale = LanguageController.current.intlLocale
        format.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let end else { return start.formatted(format) }
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }

    private var ruleText: String {
        var text =
            row.belowTarget
            ? L10n.text(K.alerts.card.alertsTarget, ["price": Fmt.currency(row.target ?? 0, code: row.currency)])
            : L10n.text(K.alerts.card.alertsDrops)
        if row.emailEnabled { text += " · " + L10n.text(K.alerts.card.alsoEmail) }
        return text
    }

    private var noPriceText: String {
        if row.isPast { return L10n.text(K.alerts.card.noPriceFound) }
        if row.isErrored { return L10n.text(K.alerts.card.noPriceYet) }
        return L10n.text(K.alerts.card.gettingPrice)
    }

    /// The move since the baseline: down is good news, up is bad.
    private var changeText: (text: String, family: Family?)? {
        guard let price = row.price, let baseline = row.baseline else { return nil }
        let delta = price - baseline
        if abs(delta) < 0.005 { return (text: L10n.text(K.alerts.change.same), family: nil) }
        let amount = Fmt.currency(abs(delta), code: row.currency)
        if delta < 0 { return (text: L10n.text(K.alerts.change.less, ["amount": amount]), family: Family.emerald) }
        return (text: L10n.text(K.alerts.change.more, ["amount": amount]), family: Family.rose)
    }
}
