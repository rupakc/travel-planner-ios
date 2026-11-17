import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Head-to-head on the Play hub: the caller's matches (with their state) and a form to challenge a friend by handle.
struct H2HSectionView: View {
    @Bindable var model: H2HListModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.play.h2h.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityAddTraits(.isHeader)
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(verbatim: L10n.text(K.play.h2h.hint)).font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                    matches
                    Divider().overlay(SemanticColor.border)
                    form
                }
            }
        }
        .accessibilityIdentifier("play.h2h")
    }

    @ViewBuilder private var matches: some View {
        if model.phase == .loading {
            ProgressView { Text(verbatim: L10n.text(K.play.loading)) }.frame(maxWidth: .infinity)
        } else if model.phase == .failed {
            Text(verbatim: L10n.text(K.errors.generic)).font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.destructive).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("play.h2h.failed")
            VButton(L10n.text(K.social.feed.retry), tid: "play.h2h.retry", role: .secondary) { Task { await model.load() } }
        } else if model.matches.isEmpty {
            Text(verbatim: L10n.text(K.play.h2h.empty)).font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("play.h2h.empty")
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(model.matches) { match in
                    MatchRow(match: match) { model.open(match) }
                }
            }
            .accessibilityIdentifier("play.h2h.list")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.play.h2h.handle)).font(VFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(SemanticColor.text).accessibilityHidden(true)
            TextField("", text: $model.handle)
                .playField()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .autocorrectionDisabled()
                .accessibilityLabel(Text(verbatim: L10n.text(K.play.h2h.handle)))
                .accessibilityIdentifier("play.h2h.handle")
            Text(verbatim: L10n.text(K.play.h2h.pack)).font(VFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(SemanticColor.text).accessibilityHidden(true)
            Menu {
                Picker(L10n.text(K.play.h2h.pack), selection: $model.pack) {
                    ForEach(H2HListModel.packs, id: \.self) { id in
                        Text(verbatim: QuizText.packName(id)).tag(id)
                    }
                }
            } label: {
                HStack {
                    Text(verbatim: QuizText.packName(model.pack)).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                        .foregroundStyle(SemanticColor.textMuted).accessibilityHidden(true)
                }
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .borderedSurface(
                    RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
            }
            .accessibilityLabel(Text(verbatim: L10n.text(K.play.h2h.pack) + ": " + QuizText.packName(model.pack)))
            .accessibilityIdentifier("play.h2h.pack")
            if let text = model.errorText {
                Text(verbatim: text).font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.h2h.error")
            }
            VButton(L10n.text(K.play.h2h.create), tid: "play.h2h.create") { Task { await model.create() } }
                .disabled(!model.canCreate)
        }
        // The field, its labels and the picker hold a handle or a pack name: capped so a word never breaks mid-word.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// One match: the opponent's handle (verbatim), where it stands, the score once it is finished, and "Open".
private struct MatchRow: View {
    let match: H2HMatch
    let open: () -> Void

    var body: some View {
        // One layout for every row: decided by the size category, not per row, so the buttons line up.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    texts
                    openButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.md) {
                    texts
                    Spacer(minLength: Spacing.sm)
                    openButton
                }
            }
        }
        // A handle is one unbreakable word: capped so it never breaks mid-word at the largest sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: match.opponent).font(VFont.body(.body, weight: .semibold)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: H2HText.state(match.state)).font(VFont.body(.subheadline))
                .foregroundStyle(match.state == .waitingYou ? SemanticColor.primary : SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let score = H2HText.score(match) {
                Text(verbatim: score).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var openButton: some View {
        VButton(L10n.text(K.play.h2h.open), tid: "play.h2h.open", role: .secondary, action: open)
            .fixedSize(horizontal: true, vertical: false)
    }
}
