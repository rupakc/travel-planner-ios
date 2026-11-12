import DesignSystem
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerModel

/// The route, the dates, the Travel Ease grade, the "AI paused" banner and the progress line.
struct ResultsHeader: View {
    let request: TravelSearchRequest
    let state: ResultsState
    let ctx: SectionContext
    let interrupted: Bool
    let failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: routeText)
                        .font(VFont.display(.title3))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let dates = datesText {
                        Text(verbatim: dates)
                            .font(VFont.body(.subheadline))
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                    Text(verbatim: progressText)
                        .font(VFont.body(.footnote))
                        .foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let confidence = state.confidence {
                ConfidenceHeaderView(data: confidence, ctx: ctx)
            }
            if let banner = state.banner { notice(banner) }
            if interrupted { notice(L10n.text(K.sections.page.interrupted)) }
            if let failure { notice(failure) }
        }
        .accessibilityIdentifier("results.header")
    }

    private func notice(_ text: String) -> some View {
        Label {
            Text(verbatim: text)
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.color(.amber, .s700)).accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.color(.amber, .s100), in: RoundedRectangle(cornerRadius: Radius.itemCard))
    }

    private var routeText: String {
        let stops = (request.destinations?.isEmpty == false ? request.destinations : request.destination.map { [$0] }) ?? []
        let places = [request.origin].compactMap { $0 } + stops
        return places.isEmpty
            ? L10n.text(K.sections.page.gettingReady)
            : places.joined(separator: " \u{2192} ")
    }

    private var datesText: String? {
        let from = Self.date(request.departureDate)
        let to = Self.date(request.returnDate)
        switch (from, to) {
        case (let from?, let to?): return "\(from) \u{2013} \(to)"
        case (let from?, nil): return from
        default: return nil
        }
    }

    private var progressText: String {
        if state.done { return L10n.text(K.sections.page.ready) }
        let total = SectionID.allCases.count
        return L10n.text(K.sections.page.almostThere, ["done": String(state.completedCount), "total": String(total)])
    }

    /// `YYYY-MM-DD` shown in the app language.
    static func date(_ string: String?) -> String? {
        guard let string, string.count >= 10 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return string
        }
        return Fmt.date(date)
    }
}
