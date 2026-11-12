import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The last eight searches: tap loads one into the form, swipe left (or the VoiceOver action) removes it.
struct RecentSearchesList: View {
    let model: SearchFormModel

    var body: some View {
        if !model.recents.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.search.recent.title))
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                VStack(spacing: Spacing.sm) {
                    ForEach(model.recents, id: \.id) { recent in
                        SwipeToDeleteRow(
                            removeLabel: L10n.text(K.search.recent.removeAria, ["route": Self.route(recent)]),
                            onDelete: { model.deleteRecent(recent) },
                            content: {
                                Button { model.fill(from: recent) } label: { row(recent) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("search.recent.\(recent.id)")
                            })
                    }
                }
            }
        }
    }

    private func row(_ recent: RecentSearch) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: Self.route(recent))
                .font(VFont.body(.body, weight: .medium))
                .foregroundStyle(SemanticColor.text)
            Text(verbatim: Self.detail(recent))
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(SemanticColor.border, lineWidth: 1) }
        .contentShape(Rectangle())
    }

    static func route(_ recent: RecentSearch) -> String {
        let search = recent.search
        let from = SearchFormModel.short(search["origin"].string ?? "")
        let to = SearchFormModel.short(search["destination"].string ?? "")
        return "\(from) → \(to)"
    }

    static func detail(_ recent: RecentSearch) -> String {
        let search = recent.search
        let start = search["departure_date"].string ?? ""
        let end = search["return_date"].string
        return [start, end].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
    }
}

/// A row that slides left to reveal a delete action; a full swipe removes it. VoiceOver gets a named action.
struct SwipeToDeleteRow<Content: View>: View {
    let removeLabel: String
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var offset: CGFloat = 0

    private let revealWidth: CGFloat = 72
    private let fullSwipe: CGFloat = 160

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(SemanticColor.onPrimary)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(SemanticColor.destructive, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .opacity(offset < 0 ? 1 : 0)
            .accessibilityHidden(true)
            content()
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, value.translation.width)
                        }
                        .onEnded { value in
                            if value.translation.width < -fullSwipe {
                                onDelete()
                            } else {
                                withAnimation(.snappy) { offset = value.translation.width < -revealWidth / 2 ? -revealWidth : 0 }
                            }
                        }
                )
        }
        .accessibilityAction(named: removeLabel, onDelete)
    }
}
