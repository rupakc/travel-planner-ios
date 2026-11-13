import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Local transport (api-contract 3.4.12), grouped In the City / Between Cities / Other as on the web.
public struct GettingAroundSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    /// Options split by `scope`; unknown scopes go to "other". Empty groups are omitted.
    static func groups(_ options: [JSONValue]) -> [(title: LKey, options: [JSONValue])] {
        let city = options.filter { $0["scope"].string == "intra_city" }
        let between = options.filter { $0["scope"].string == "inter_city" }
        let other = options.filter { !["intra_city", "inter_city"].contains($0["scope"].string ?? "") }
        return [
            (K.results.transport.inCity, city), (K.results.transport.betweenCities, between),
            (K.results.transport.other, other),
        ].filter { !$0.1.isEmpty }.map { (title: $0.0, options: $0.1) }
    }

    public var body: some View {
        let options = Info.list(data, "options")
        if options.isEmpty {
            InfoEmpty(key: K.results.transport.none)
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(Self.groups(options).enumerated()), id: \.offset) { _, group in
                    InfoHeading(title: L10n.text(group.title))
                    ForEach(Array(group.options.enumerated()), id: \.offset) { _, option in card(option) }
                }
            }
        }
    }

    private func card(_ option: JSONValue) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: SectionItem(option).name ?? "")
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let type = Info.text(option["type"]) { InfoTag(title: type, family: .sky) }
                InfoLine(label: nil, value: Info.text(option["description"]))
                InfoLine(label: L10n.text(K.results.transport.coverage), value: Info.text(option["coverage"]))
                InfoLine(label: L10n.text(K.results.transport.price), value: Info.text(option["price_info"]))
                InfoLine(label: L10n.text(K.results.transport.hours), value: Info.text(option["operating_hours"]))
                InfoLine(label: L10n.text(K.results.transport.touristPass), value: Info.text(option["tourist_pass"]))
                InfoLine(label: nil, value: Info.text(option["tips"]))
                HStack {
                    InfoLink(
                        title: L10n.text(K.results.transport.moreInfo), url: Info.httpsURL(option["booking_url"]),
                        section: "getting_around", ctx: ctx)
                    Spacer(minLength: 0)
                    PlanToggle(field: "getting_around", item: option, ctx: ctx)
                }
            }
        }
    }
}
