import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// "Want us to watch these prices?" for a saved plan. Shows nothing without live prices (plan ruling R3). The host
/// presents it (a sheet) and passes `onClose`; the sheet reports `alert_suggest` and closes itself on "Not now" / "Done".
public struct SuggestionsSheet: View {
    @State private var model: SuggestionsModel
    private let onClose: () -> Void
    /// False for snapshots, whose rows were set up by hand.
    private let loadsOnAppear: Bool

    @MainActor public init(env: AppEnvironment, planID: Int, onClose: @escaping () -> Void) {
        _model = State(initialValue: SuggestionsModel(env: env, planID: planID))
        self.onClose = onClose
        loadsOnAppear = true
    }

    @MainActor init(model: SuggestionsModel, loadsOnAppear: Bool = true, onClose: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onClose = onClose
        self.loadsOnAppear = loadsOnAppear
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(Spacing.xl)
                case .failed(let message):
                    VStack(spacing: Spacing.md) {
                        Text(verbatim: message).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                        VButton(L10n.text(K.watchSuggest.retry), tid: "suggestions.retry", role: .secondary) {
                            Task { await model.load() }
                        }
                        close
                    }
                case .hidden:
                    EmptyView()
                case .loaded:
                    content
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .task { if loadsOnAppear { await model.load() } }
        .accessibilityIdentifier("suggestions.root")
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(K.watchSuggest.title))
                .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: L10n.text(K.watchSuggest.subtitle))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(model.rows) { row in
                    SuggestionRow(row: row, isLocked: model.isWatching) { model.toggle(row.id) }
                    if row.id != model.rows.last?.id { Divider() }
                }
            }
        }
        if model.isFinished {
            VButton(L10n.text(K.watchSuggest.done), tid: "suggestions.done", role: .primary) { closeAndReport() }
        } else {
            VButton(
                L10n.text(K.watchSuggest.watchN, count: model.selectedCount), tid: "suggestions.watch", role: .primary,
                systemImage: "bell"
            ) { Task { await model.watchSelected() } }
            .disabled(!model.canWatch)
            close
        }
    }

    private var close: some View {
        VButton(L10n.text(K.watchSuggest.notNow), tid: "suggestions.notNow", role: .secondary) { closeAndReport() }
    }

    private func closeAndReport() {
        model.dismiss()
        onClose()
    }
}
