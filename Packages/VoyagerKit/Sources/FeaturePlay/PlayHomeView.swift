import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The Play hub (`router.open(.play)`): daily quiz, weekly challenge, practice packs, open matches and recent games.
/// Everything shown comes from the server; the hub never computes a score or a streak.
public struct PlayHomeView: View {
    @State private var model: PlayHomeModel
    @Environment(\.dynamicTypeSize) private var typeSize

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: PlayHomeModel(env: env))
    }

    @MainActor init(model: PlayHomeModel) {
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
        .navigationTitle(Text(verbatim: L10n.text(K.playYou.page.title)))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .onAppear { Task { await model.refreshIfNeeded() } }
        .refreshable { await model.load() }
        .accessibilityIdentifier("play.home")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.play.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
        case .unavailable(let gameHidden):
            EmptyState(
                icon: "gamecontroller",
                title: gameHidden ? L10n.text(K.playYou.hidden.note) : L10n.text(K.play.home.unavailable))
                .accessibilityIdentifier("play.unavailable")
        case .failed(let kind, let detail):
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: ErrorCopy.message(kind: kind, detail: detail)).font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.destructive).fixedSize(horizontal: false, vertical: true)
                VButton(L10n.text(K.social.feed.retry), tid: "play.retry", role: .secondary) { Task { await model.load() } }
            }
        case .loaded:
            loaded
        }
    }

    @ViewBuilder private var loaded: some View {
        if let text = model.errorText {
            Text(verbatim: text).font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.error")
        }
        dailyCard
        if model.openMatches > 0 {
            Text(verbatim: L10n.text(K.play.home.openH2H, count: model.openMatches))
                .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.openH2H")
        }
        if let challenge = model.challenge { challengeCard(challenge) }
        if !model.packs.isEmpty { packsCard }
        if !model.history.isEmpty { historyCard }
    }

    private var dailyCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.play.daily.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: L10n.text(K.play.daily.hint)).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if model.daily.streak.current > 0 {
                    Text(verbatim: L10n.text(K.play.daily.streak, count: model.daily.streak.current))
                        .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                        .accessibilityIdentifier("play.daily.streak")
                    if model.daily.streak.freezeAvailable {
                        Text(verbatim: L10n.text(K.play.home.freeze)).font(VFont.body(.footnote))
                            .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.daily.done {
                    Text(verbatim: L10n.text(K.play.daily.done, count: model.daily.score ?? 0))
                        .font(VFont.body(.body, weight: .semibold)).foregroundStyle(SemanticColor.primary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.daily.done")
                } else {
                    VButton(L10n.text(K.play.daily.start), tid: "play.daily.start", systemImage: "play.fill") {
                        Task { await model.startDaily() }
                    }
                    .disabled(model.isBusy || !model.daily.available)
                }
            }
        }
    }

    private func challengeCard(_ challenge: PlayChallenge) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.play.challenge.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: challengeText(challenge)).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if challenge.done {
                    Text(verbatim: L10n.text(K.play.challenge.done)).font(VFont.body(.body, weight: .semibold))
                        .foregroundStyle(SemanticColor.primary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("play.challenge")
    }

    private func challengeText(_ challenge: PlayChallenge) -> String {
        if challenge.kind == .destination, let country = challenge.country, !country.isEmpty {
            let name = country.count == 2 ? QuizText.regionName(code: country, fallback: country) : country
            return L10n.text(K.play.challenge.destination, ["country": name])
        }
        return L10n.text(K.play.challenge.featured)
    }

    private var packsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.play.packs.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 400 : 130), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(model.packs) { pack in
                    PackTile(title: QuizText.packName(pack.id), tid: "play.pack.\(pack.id)", busy: model.isBusy) {
                        Task { await model.startPack(pack) }
                    }
                }
            }
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.play.home.history)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(model.history) { entry in HistoryRow(entry: entry) }
                }
            }
        }
        .accessibilityIdentifier("play.history")
    }
}

/// One practice pack: a large tappable tile (44 pt minimum, wraps at word boundaries).
private struct PackTile: View {
    let title: String
    let tid: String
    let busy: Bool
    let action: () -> Void
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: tid, route: route))
            action()
        } label: {
            Text(verbatim: title).font(VFont.body(.body, weight: .semibold)).foregroundStyle(SemanticColor.text)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                .borderedSurface(
                    RoundedRectangle(cornerRadius: Radius.itemCard), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
        .accessibilityIdentifier(tid)
    }
}

/// A finished game: what it was, and the score the server recorded.
private struct HistoryRow: View {
    let entry: QuizHistoryEntry

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: Spacing.sm)
                score.multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                score
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text(verbatim: QuizText.modeName(mode: entry.mode, pack: entry.pack))
            .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var score: some View {
        Text(verbatim: L10n.text(K.play.board.points, count: entry.score))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
