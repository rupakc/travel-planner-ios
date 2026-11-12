import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// The ten interests as toggle chips.
struct InterestPicker: View {
    let model: SearchFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.search.form.interests))
                .font(VFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
            FlowLayout(spacing: Spacing.sm) {
                ForEach(SearchFormModel.interestIDs, id: \.self) { id in
                    VChip(title: Self.label(id), tid: "search.interest.\(id)", selected: model.interests.contains(id)) {
                        model.toggleInterest(id)
                    }
                }
            }
        }
    }

    static func label(_ id: String) -> String {
        switch id {
        case "adventure": L10n.text(K.search.interests.adventure)
        case "art": L10n.text(K.search.interests.art)
        case "culture": L10n.text(K.search.interests.culture)
        case "family": L10n.text(K.search.interests.family)
        case "food": L10n.text(K.search.interests.food)
        case "history": L10n.text(K.search.interests.history)
        case "nature": L10n.text(K.search.interests.nature)
        case "nightlife": L10n.text(K.search.interests.nightlife)
        case "shopping": L10n.text(K.search.interests.shopping)
        default: L10n.text(K.search.interests.wellness)
        }
    }
}

/// Free-text tags (residence permits, existing visas): Return or a comma adds one, a tag's x removes it.
struct TagInput: View {
    let label: String
    let placeholder: String
    let tid: String
    @Binding var tags: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: label)
                .font(VFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if !tags.isEmpty {
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(tags, id: \.self) { tag in
                            Button { tags.removeAll { $0 == tag } } label: {
                                HStack(spacing: Spacing.xs) {
                                    Text(verbatim: tag)
                                    Image(systemName: "xmark").font(.caption)
                                }
                                .font(VFont.body(.subheadline, weight: .medium))
                                .foregroundStyle(SemanticColor.primary)
                                .padding(.horizontal, Spacing.md)
                                .frame(minHeight: 44)
                                .background(SemanticColor.surfaceRaised, in: Capsule())
                                .overlay { Capsule().strokeBorder(SemanticColor.primary, lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tag)
                            .accessibilityIdentifier("\(tid).tag.\(tag)")
                        }
                    }
                }
                TextField(placeholder, text: $draft)
                    .font(VFont.body(.body))
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 44)
                    .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(SemanticColor.border, lineWidth: 1) }
                    .onSubmit { commit() }
                    .onChange(of: draft) { _, value in
                        if value.contains(",") {
                            for part in value.split(separator: ",") { add(String(part)) }
                            draft = ""
                        }
                    }
                    .accessibilityIdentifier(tid)
            }
            Text(verbatim: L10n.text(K.search.tags.hint))
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
        }
    }

    private func commit() {
        add(draft)
        draft = ""
    }

    private func add(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty, !tags.contains(tag) { tags.append(tag) }
    }
}

/// Wraps its children onto rows (a lazy-free `Layout`, so it renders in hosted snapshots).
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
