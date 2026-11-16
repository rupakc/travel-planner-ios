import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// One match (`router.open(.h2h(id:))`): accept or decline, wait, or the finished result. The opponent's score is shown
/// only when the match is done.
public struct H2HMatchView: View {
    @State private var model: H2HMatchModel
    @Environment(\.dismiss) private var dismiss

    @MainActor public init(env: AppEnvironment, matchID: String) {
        _model = State(initialValue: H2HMatchModel(env: env, matchID: matchID))
    }

    @MainActor init(model: H2HMatchModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) { content }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
        }
        .background(SemanticColor.surface)
        .navigationTitle(Text(verbatim: L10n.text(K.play.h2h.title)))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .onAppear { Task { await model.refreshIfNeeded() } }
        .onChange(of: model.declined) { _, declined in if declined { dismiss() } }
        .accessibilityIdentifier("play.h2h.match")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.play.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
        case .unavailable:
            EmptyState(icon: "gamecontroller", title: L10n.text(K.play.home.unavailable))
            back
        case .missing:
            Text(verbatim: L10n.text(K.play.h2h.missing)).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.h2h.missing")
            back
        case .failed(let message):
            Text(verbatim: message).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.h2h.failed")
            PlayButton(L10n.text(K.social.feed.retry), tid: "play.h2h.retry", role: .secondary) { Task { await model.load() } }
            back
        case .loaded:
            if let match = model.match { matchCard(match) }
        }
    }

    private var back: some View {
        PlayButton(L10n.text(K.play.h2h.back), tid: "play.h2h.back", role: .secondary) { dismiss() }
    }

    private func matchCard(_ match: H2HMatch) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.play.h2h.vs, ["handle": match.opponent])).font(VFont.display(.title3))
                    .foregroundStyle(SemanticColor.text).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Text(verbatim: H2HText.state(match.state)).font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("play.h2h.state")
                if match.state == .done {
                    if let score = H2HText.score(match) {
                        Text(verbatim: score).font(VFont.display(.largeTitle)).foregroundStyle(SemanticColor.primary)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("play.h2h.score")
                    }
                    Text(verbatim: H2HText.winner(match.winner)).font(VFont.body(.body, weight: .semibold))
                        .foregroundStyle(SemanticColor.text).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("play.h2h.winner")
                }
                if let text = model.errorText {
                    Text(verbatim: text).font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.destructive)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.h2h.error")
                }
                if match.state == .waitingYou {
                    PlayButton(L10n.text(K.play.h2h.accept), tid: "play.h2h.accept") { Task { await model.accept() } }
                        .disabled(model.busy)
                    PlayButton(L10n.text(K.play.h2h.decline), tid: "play.h2h.decline", role: .secondary) {
                        Task { await model.decline() }
                    }
                    .disabled(model.busy)
                }
                back
            }
        }
    }
}
