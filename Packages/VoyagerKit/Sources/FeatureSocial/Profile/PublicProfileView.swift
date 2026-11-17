import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// Someone's profile (`router.open(.profile(handle:))`). All user text (handle, bio, idea titles) is plain `verbatim` text.
public struct PublicProfileView: View {
    @State private var model: PublicProfileModel
    private let env: AppEnvironment

    @MainActor public init(env: AppEnvironment, handle: String) {
        self.env = env
        _model = State(initialValue: PublicProfileModel(env: env, handle: handle))
    }

    @MainActor init(model: PublicProfileModel) {
        env = model.env
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
        .navigationTitle(Text(verbatim: L10n.text(K.social.profile.of, ["handle": model.handle])))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: model.noticeText) { _, text in
            if let text { LiveRegion.announce(text) }
        }
        .confirmationDialog(
            L10n.text(K.social.block.confirm, ["handle": model.handle]), isPresented: $model.confirmingBlock, titleVisibility: .visible
        ) {
            Button(L10n.text(K.social.block.yes), role: .destructive) { Task { await model.confirmBlock() } }
            Button(L10n.text(K.social.actions.cancel), role: .cancel) {}
        }
        .sheet(isPresented: $model.reporting) {
            ProfileReportView(model: ProfileReportModel(env: env, handle: model.handle)) {
                model.reporting = false
            }
        }
        .accessibilityIdentifier("profile.public")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.social.feed.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
        case .unavailable, .notFound:
            EmptyState(icon: "person.crop.circle.badge.questionmark", title: L10n.text(K.social.profile.notFound))
                .accessibilityIdentifier("profile.notFound")
        case .failed(let kind, let detail):
            ProfileFailureView(message: ErrorCopy.message(kind: kind, detail: detail), tid: "profile.retry") {
                Task { await model.load() }
            }
        case .loaded:
            if let profile = model.profile { loaded(profile) }
        }
    }

    @ViewBuilder private func loaded(_ profile: PublicProfile) -> some View {
        header(profile)
        actions
        if let text = model.noticeText { notice(text) }
        ideasSection
    }

    private func header(_ profile: PublicProfile) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: "@" + profile.handle)
                    .font(VFont.display(.title2)).foregroundStyle(SemanticColor.text)
                    // A handle is one word of up to 20 characters: it scales down instead of breaking mid-word.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
                if model.followsYou {
                    VChip(title: L10n.text(K.social.profile.followsYou), tid: "profile.followsYou", selected: false) {}
                        .allowsHitTesting(false)
                }
                if !profile.bio.isEmpty {
                    Text(verbatim: profile.bio)
                        .font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let country = model.countryName {
                    Text(verbatim: L10n.text(K.social.profile.from, ["country": country]))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.showsLevel, let level = profile.level {
                    Text(verbatim: L10n.text(K.social.profile.level, ["level": String(level)]))
                        .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                }
                if model.showsBadges, let badges = profile.badges {
                    detail(L10n.text(K.social.profile.badges), badges.map { BadgeNames.name($0.id) }.joined(separator: ", "))
                }
                if !model.visitedNames.isEmpty {
                    detail(L10n.text(K.social.profile.visited), model.visitedNames.joined(separator: ", "))
                }
                counts(profile)
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.textMuted)
            // Capped at accessibility2 so a long German compound ("Passstempel") never breaks mid-word at AX5.
            Text(verbatim: value).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func counts(_ profile: PublicProfile) -> some View {
        let items = [
            (L10n.text(K.social.profile.ideas), profile.ideasCount),
            (L10n.text(K.social.profile.followers), profile.followersCount),
            (L10n.text(K.social.profile.followingLabel), profile.followingCount),
        ]
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.lg) { ForEach(items, id: \.0) { count($0.0, $0.1) } }
            VStack(alignment: .leading, spacing: Spacing.sm) { ForEach(items, id: \.0) { count($0.0, $0.1) } }
        }
    }

    private func count(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: String(value)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
            Text(verbatim: title).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var actions: some View {
        if model.isMine {
            VButton(L10n.text(K.social.profile.edit), tid: "profile.edit", role: .secondary) { model.openEditor() }
        } else {
            VButton(followTitle, tid: "profile.follow", role: model.relation == .none ? .primary : .secondary) {
                Task { await model.toggleFollow() }
            }
            .disabled(model.working)
            .accessibilityHint(followHint)
            ActionPair {
                VButton(L10n.text(K.social.report.title), tid: "profile.report", role: .secondary) { model.reporting = true }
            } second: {
                VButton(L10n.text(K.social.block.block), tid: "profile.block", role: .destructive) { model.askBlock() }
            }
        }
    }

    private var followTitle: String {
        switch model.relation {
        case .none: L10n.text(K.social.profile.follow)
        case .pending: L10n.text(K.social.profile.requested)
        case .following: L10n.text(K.social.profile.following)
        }
    }

    private var followHint: String {
        switch model.relation {
        case .none: ""
        case .pending: L10n.text(K.social.profile.cancelRequest)
        case .following: L10n.text(K.social.profile.stopFollowing)
        }
    }

    private func notice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            let isError: Bool = { if case .failed = model.notice { return true }; return false }()
            Text(verbatim: text)
                .font(VFont.body(.footnote, weight: .semibold))
                .foregroundStyle(isError || model.notice == .profileRequired ? SemanticColor.destructive : SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if model.notice == .profileRequired {
                VButton(L10n.text(K.social.feed.createProfile), tid: "profile.createFirst", role: .secondary) { model.openEditor() }
            }
        }
        .accessibilityIdentifier("profile.notice")
    }

    @ViewBuilder private var ideasSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.social.profile.ideas))
                .font(VFont.display(.headline)).foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            if model.visibleIdeas.isEmpty {
                Text(verbatim: L10n.text(K.social.profile.noIdeas))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            }
            ForEach(model.visibleIdeas) { idea in
                Button { model.open(idea) } label: {
                    VCard {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(verbatim: idea.title)
                                .font(VFont.body(.body, weight: .semibold)).foregroundStyle(SemanticColor.text)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            if idea.status == .held {
                                Text(verbatim: L10n.text(K.social.idea.held))
                                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if model.canLoadMoreIdeas {
                VButton(L10n.text(K.social.feed.loadMore), tid: "profile.moreIdeas", role: .secondary) {
                    Task { await model.loadIdeas() }
                }
            }
        }
    }
}
