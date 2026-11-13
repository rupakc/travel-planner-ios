import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// What the filter sheet edits, for flights, hotels or activities. The backend filters (`/api/<section>/filtered`)
/// are `serverFilters`; `minStars` is applied on the device to the hotels the server returned.
struct FilterDraft: Equatable {
    var maxStops: Int?
    var maxPrice = ""
    var minStars: Int?
    var wifi: String?
    var privateWashroom = false
    var interests: Set<String> = []
    var minRating: Double?

    var price: Double? {
        let text = maxPrice.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// The `/filtered` body fields for `section` (only the set ones).
    func serverFilters(for section: FilterableSection) -> JSONValue {
        var fields: [String: JSONValue] = [:]
        switch section {
        case .flights:
            if let maxStops { fields["max_stops"] = .number(Double(maxStops)) }
            if let price { fields["max_price_usd"] = .number(price) }
        case .hotels:
            if let price { fields["max_price_per_night_usd"] = .number(price) }
            if let wifi { fields["wifi_quality"] = .string(wifi) }
            if privateWashroom { fields["private_washroom"] = .bool(true) }
        case .activities:
            if !interests.isEmpty { fields["filter_interests"] = .array(interests.sorted().map(JSONValue.string)) }
            if let price { fields["max_price_usd"] = .number(price) }
            if let minRating { fields["min_rating"] = .number(minRating) }
        }
        return .object(fields)
    }

    func activeCount(for section: FilterableSection) -> Int {
        (serverFilters(for: section).object?.count ?? 0) + (section == .hotels && minStars != nil ? 1 : 0)
    }

    static let interestIDs = ["food", "history", "adventure", "culture", "nature", "shopping", "nightlife", "wellness", "art", "family"]
}

/// The filter sheet. Apply hands the draft back; Clear All resets it.
struct FilterSheet: View {
    let section: FilterableSection
    @Binding var draft: FilterDraft
    let busy: Bool
    let onApply: () -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch section {
        case .flights: L10n.text(K.results.flights.filterTitle)
        case .hotels: L10n.text(K.results.hotels.filterTitle)
        case .activities: L10n.text(K.results.activities.filterTitle)
        }
    }

    private var priceLabel: String {
        switch section {
        case .flights: L10n.text(K.results.flights.maxPrice)
        case .hotels: L10n.text(K.results.hotels.maxCost)
        case .activities: L10n.text(K.results.activities.maxCost)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    switch section {
                    case .flights: stopsGroup
                    case .hotels: starsGroup
                    case .activities: categoryGroup
                    }
                    priceField
                    switch section {
                    case .hotels: hotelExtras
                    case .activities: ratingGroup
                    case .flights: EmptyView()
                    }
                    HStack(spacing: Spacing.sm) {
                        VButton(L10n.text(K.results.filter.clearAll), tid: "results.filter.clear", role: .secondary) {
                            onClear()
                        }
                        VButton(
                            L10n.text(busy ? K.results.filter.searching : K.results.filter.apply), tid: "results.filter.apply"
                        ) {
                            onApply()
                            dismiss()
                        }
                        .disabled(busy)
                    }
                }
                .padding(Spacing.lg)
            }
            .background(SemanticColor.surface)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(K.results.common.close)) { dismiss() }
                        .accessibilityIdentifier("results.filter.close")
                }
            }
        }
    }

    // MARK: Groups

    private func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: label).font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            FlowChips { content() }
        }
    }

    private var stopsGroup: some View {
        group(L10n.text(K.results.flights.numStops)) {
            VChip(title: L10n.text(K.results.filter.any), tid: "results.filter.stops.any", selected: draft.maxStops == nil) {
                draft.maxStops = nil
            }
            VChip(title: L10n.text(K.results.flights.direct), tid: "results.filter.stops.0", selected: draft.maxStops == 0) {
                draft.maxStops = 0
            }
            ForEach([1, 2], id: \.self) { count in
                VChip(
                    title: L10n.text(K.results.flights.stopsBtn, count: count), tid: "results.filter.stops.\(count)",
                    selected: draft.maxStops == count
                ) { draft.maxStops = count }
            }
        }
    }

    private var starsGroup: some View {
        group(L10n.text(K.sections.commerce.minStars)) {
            VChip(title: L10n.text(K.results.filter.any), tid: "results.filter.stars.any", selected: draft.minStars == nil) {
                draft.minStars = nil
            }
            ForEach([3, 4, 5], id: \.self) { stars in
                VChip(title: "\(stars)★", tid: "results.filter.stars.\(stars)", selected: draft.minStars == stars) {
                    draft.minStars = stars
                }
            }
        }
    }

    private static let wifiLevels: [(String, LKey)] = [
        ("basic", K.results.hotels.wifi.basic), ("good", K.results.hotels.wifi.good), ("excellent", K.results.hotels.wifi.excellent),
    ]

    private var hotelExtras: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            group(L10n.text(K.results.hotels.wifiQuality)) {
                VChip(title: L10n.text(K.results.filter.any), tid: "results.filter.wifi.any", selected: draft.wifi == nil) {
                    draft.wifi = nil
                }
                ForEach(Self.wifiLevels, id: \.0) { code, key in
                    VChip(title: L10n.text(key), tid: "results.filter.wifi.\(code)", selected: draft.wifi == code) { draft.wifi = code }
                }
            }
            Toggle(isOn: $draft.privateWashroom) {
                Text(verbatim: L10n.text(K.results.hotels.privateWashroom)).font(VFont.body(.subheadline))
            }
            .accessibilityIdentifier("results.filter.washroom")
        }
    }

    private var categoryGroup: some View {
        group(L10n.text(K.results.activities.interests)) {
            ForEach(FilterDraft.interestIDs, id: \.self) { id in
                VChip(title: Self.interestTitle(id), tid: "results.filter.category.\(id)", selected: draft.interests.contains(id)) {
                    if draft.interests.contains(id) { draft.interests.remove(id) } else { draft.interests.insert(id) }
                }
            }
        }
    }

    private var ratingGroup: some View {
        group(L10n.text(K.results.activities.minRating)) {
            VChip(title: L10n.text(K.results.filter.any), tid: "results.filter.rating.any", selected: draft.minRating == nil) {
                draft.minRating = nil
            }
            ForEach([3.0, 4.0, 4.5], id: \.self) { rating in
                VChip(
                    title: "★ \(Fmt.number(rating, fractionDigits: 1))+", tid: "results.filter.rating.\(Int(rating * 10))",
                    selected: draft.minRating == rating
                ) {
                    draft.minRating = rating
                }
            }
        }
    }

    private var priceField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: priceLabel).font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            TextField(text: $draft.maxPrice, prompt: Text(verbatim: L10n.text(K.results.filter.any))) {
                Text(verbatim: priceLabel)
            }
            .decimalKeyboard()
            .padding(Spacing.md)
            .frame(minHeight: 44)
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.input))
            .overlay { RoundedRectangle(cornerRadius: Radius.input).strokeBorder(SemanticColor.border, lineWidth: 1) }
            .accessibilityIdentifier("results.filter.price")
        }
    }

    static func interestTitle(_ id: String) -> String {
        switch id {
        case "food": L10n.text(K.results.interests.food)
        case "history": L10n.text(K.results.interests.history)
        case "adventure": L10n.text(K.results.interests.adventure)
        case "culture": L10n.text(K.results.interests.culture)
        case "nature": L10n.text(K.results.interests.nature)
        case "shopping": L10n.text(K.results.interests.shopping)
        case "nightlife": L10n.text(K.results.interests.nightlife)
        case "wellness": L10n.text(K.results.interests.wellness)
        case "art": L10n.text(K.results.interests.art)
        default: L10n.text(K.results.interests.family)
        }
    }
}

extension View {
    @ViewBuilder fileprivate func decimalKeyboard() -> some View {
        #if canImport(UIKit)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder fileprivate func navigationBarTitleDisplayModeInline() -> some View {
        #if canImport(UIKit)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full.
struct WrapLayout: Layout {
    var spacing: CGFloat = Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in rows.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private struct Arrangement {
        let origins: [CGPoint]
        let width: CGFloat
        let height: CGFloat
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return Arrangement(origins: origins, width: widest, height: y + rowHeight)
    }
}

/// Wrapping row of chips.
struct FlowChips<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        WrapLayout { content }
    }
}
