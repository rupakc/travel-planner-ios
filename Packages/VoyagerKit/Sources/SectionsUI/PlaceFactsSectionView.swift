import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Place facts (travel-planner `docs/Place-Facts.md`, web `PlaceFactsSection.jsx`): place chips on a multi-place
/// trip, one tab per non-empty group with its count, and the group's facts. A crawler fact shows its source line
/// (name and link, as-of date, licence attribution); an AI fact is labelled "AI-suggested, not verified" and never
/// shows a source. Every fact can be added to My Plan (`selections.place_facts`). Renders nothing without facts.
public struct PlaceFactsSectionView: View {
    let data: JSONValue
    let ctx: SectionContext
    @State private var placeKey: String?
    @State private var group: String?

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let places = PlaceFacts.places(data)
        if let place = places.first(where: { $0.key == placeKey }) ?? places.first {
            let available = place.availableTypes
            let active = group.flatMap { available.contains($0) ? $0 : nil } ?? available.first ?? PlaceFacts.factTypes[0]
            let facts = place.groups[active] ?? []
            VStack(alignment: .leading, spacing: Spacing.md) {
                if places.count > 1 { placeChips(places, current: place) }
                groupTabs(place, available: available, active: active)
                VStack(spacing: Spacing.sm) {
                    ForEach(facts) { fact in FactCardView(fact: fact, place: place, ctx: ctx) }
                }
                if facts.contains(where: \.isAI) {
                    Text(verbatim: L10n.text(K.results.facts.aiNote))
                        .font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("results.facts")
        }
    }

    private func placeChips(_ places: [PlaceFacts.Place], current: PlaceFacts.Place) -> some View {
        WrapLayout(spacing: Spacing.sm) {
            ForEach(places) { item in
                VChip(title: Self.placeTitle(item), tid: "results.facts.place", selected: item.key == current.key) {
                    placeKey = item.key
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(K.results.facts.placesLabel))
    }

    private func groupTabs(_ place: PlaceFacts.Place, available: [String], active: String) -> some View {
        WrapLayout(spacing: Spacing.sm) {
            ForEach(available, id: \.self) { type in
                let count = place.groups[type]?.count ?? 0
                VChip(title: "\(Self.groupTitle(type)) (\(count))", tid: "results.facts.group", selected: type == active) {
                    group = type
                }
                .accessibilityLabel("\(Self.groupTitle(type)), \(count)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(K.results.facts.groupsLabel))
    }

    /// "Berlin · City" (the scope only when the catalogue names it).
    static func placeTitle(_ place: PlaceFacts.Place) -> String {
        guard let scope = scopeTitle(place.scope) else { return place.name }
        return "\(place.name) · \(scope)"
    }

    static func scopeTitle(_ scope: String?) -> String? {
        switch scope {
        case "city": L10n.text(K.results.facts.scope.city)
        case "place": L10n.text(K.results.facts.scope.place)
        case "region": L10n.text(K.results.facts.scope.region)
        case "country": L10n.text(K.results.facts.scope.country)
        default: nil
        }
    }

    public static func groupTitle(_ type: String) -> String {
        switch type {
        case "historical": L10n.text(K.results.facts.group.historical)
        case "fun": L10n.text(K.results.facts.group.fun)
        case "popular": L10n.text(K.results.facts.group.popular)
        case "unbelievable": L10n.text(K.results.facts.group.unbelievable)
        case "little_known": L10n.text(K.results.facts.group.little_known)
        default: type.replacingOccurrences(of: "_", with: " ")
        }
    }
}

/// One fact: its text (language-tagged), the AI label or the source line, and the My Plan toggle.
struct FactCardView: View {
    let fact: PlaceFacts.Fact
    let place: PlaceFacts.Place
    let ctx: SectionContext

    var body: some View {
        let item = PlaceFacts.selection(fact, placeName: place.name)
        let selected = ctx.isSelected(PlaceFacts.selectionField, item)
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(PlaceFacts.attributedText(fact))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Self.spokenText(fact))
                if fact.isAI {
                    // VoiceOver already hears the label first, in the fact text's label.
                    AIFactLabel(text: L10n.text(K.results.facts.aiLabel)).accessibilityHidden(true)
                } else {
                    if let citation = fact.citation { FactSourceLine(citation: citation) }
                    if fact.machineTranslated {
                        Text(verbatim: L10n.text(K.results.facts.machineTranslated))
                            .font(VFont.body(.caption2))
                            .foregroundStyle(SemanticColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    VChip(
                        title: L10n.text(selected ? K.results.plan.inPlan : K.results.plan.addToPlan), tid: "results.fact.add",
                        selected: selected
                    ) { ctx.toggle(PlaceFacts.selectionField, item) }
                    .accessibilityLabel(L10n.text(selected ? K.results.plan.inPlan : K.results.plan.addToPlan) + ": " + fact.text)
                }
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Radius.itemCard)
                    .strokeBorder(SectionAccent.color(for: "facts"), lineWidth: 1.5)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("results.fact")
    }

    /// The text VoiceOver reads, with the AI label first for an AI fact so nobody hears it as a sourced fact.
    static func spokenText(_ fact: PlaceFacts.Fact) -> Text {
        let text = Text(PlaceFacts.attributedText(fact))
        guard fact.isAI else { return text }
        return Text(verbatim: L10n.text(K.results.facts.aiLabel) + ". ") + text
    }
}

/// The amber "AI-suggested, not verified" tag.
public struct AIFactLabel: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "sparkles").accessibilityHidden(true)
        }
        .font(VFont.body(.caption, weight: .medium))
        .foregroundStyle(Palette.color(.amber, .s800))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 2)
        .background(Palette.color(.amber, .s50), in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.color(.amber, .s200), lineWidth: 1) }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("results.fact.ai")
    }
}

/// "Source: <name> · as of <date>", the licence attribution (linked to the licence) and the conflict warning:
/// the web's `SourceLine` for one crawler fact.
public struct FactSourceLine: View {
    let citation: PlaceFacts.Citation

    public init(citation: PlaceFacts.Citation) {
        self.citation = citation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let title = L10n.text(K.results.official.source, ["name": citation.name])
            let asOf = CarbonText.day(citation.asOf).map { L10n.text(K.results.official.asOf, ["date": $0]) }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                if let url = citation.url {
                    Link(destination: url) {
                        Label {
                            Text(verbatim: title)
                        } icon: {
                            Image(systemName: "arrow.up.right.square").accessibilityHidden(true)
                        }
                    }
                    .tint(SemanticColor.primary)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("results.official.source")
                } else {
                    Text(verbatim: title)
                }
                if let asOf { Text(verbatim: "· " + asOf).accessibilityLabel(asOf) }
            }
            if let attribution = citation.attribution {
                if let url = citation.licenceURL {
                    Link(destination: url) { Text(verbatim: attribution) }
                        .tint(SemanticColor.textMuted)
                } else {
                    Text(verbatim: attribution)
                }
            }
            if citation.conflict {
                Label {
                    Text(verbatim: L10n.text(K.results.official.disagree))
                } icon: {
                    Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
                }
                .foregroundStyle(Palette.color(.amber, .s700))
            }
        }
        .font(VFont.body(.caption2))
        .foregroundStyle(SemanticColor.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("results.fact.source")
    }
}

/// One fact kept in My Plan (the web's `SelectedFact`): "Place: text", then the source line for a crawler fact
/// or the AI label.
public struct SelectedFactView: View {
    let value: JSONValue
    let aiLabel: String

    public init(value: JSONValue, aiLabel: String) {
        self.value = value
        self.aiLabel = aiLabel
    }

    public var body: some View {
        if let selected = PlaceFacts.selected(value) {
            VStack(alignment: .leading, spacing: 2) {
                (placePrefix(selected.place) + Text(PlaceFacts.attributedText(selected.fact)))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(spokenText(selected))
                if selected.fact.isCrawler, let citation = selected.fact.citation {
                    FactSourceLine(citation: citation)
                } else if selected.fact.isAI {
                    Text(verbatim: aiLabel)
                        .font(VFont.body(.caption2))
                        .foregroundStyle(Palette.color(.amber, .s700))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan.fact")
        }
    }

    /// The AI label first for an AI fact (as on the Results card), then "Place: text".
    private func spokenText(_ selected: (fact: PlaceFacts.Fact, place: String?)) -> Text {
        let text = placePrefix(selected.place) + Text(PlaceFacts.attributedText(selected.fact))
        guard selected.fact.isAI else { return text }
        return Text(verbatim: aiLabel + ". ") + text
    }

    private func placePrefix(_ place: String?) -> Text {
        guard let place else { return Text(verbatim: "") }
        return Text(verbatim: place + ": ").fontWeight(.medium)
    }
}
