import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// A titled card of controls.
struct PrefsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: title)
                .font(VFont.display(.headline)).foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) { content }
            }
        }
    }
}

/// Free-text tags: a field with an add button, and removable chips.
struct TagField: View {
    let label: String
    let placeholder: String
    let tid: String
    let tags: [String]
    let add: (String) -> Void
    let remove: (String) -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: label).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            HStack(spacing: Spacing.sm) {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .frame(minHeight: 44)
                    .onSubmit(commit)
                    .accessibilityIdentifier("\(tid).input")
                Button(action: commit) {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(SemanticColor.primary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityIdentifier("\(tid).add")
            }
            if !tags.isEmpty {
                WrapLayout(spacing: Spacing.xs) {
                    ForEach(tags, id: \.self) { tag in
                        Button { remove(tag) } label: {
                            HStack(spacing: Spacing.xs) {
                                Text(verbatim: tag)
                                Image(systemName: "xmark").font(.caption2).accessibilityHidden(true)
                            }
                            .font(VFont.body(.caption))
                            .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                            .background(SemanticColor.border, in: Capsule())
                            .foregroundStyle(SemanticColor.text)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(tid).tag.\(tag)")
                    }
                }
            }
        }
    }

    private func commit() {
        add(draft)
        draft = ""
    }
}
