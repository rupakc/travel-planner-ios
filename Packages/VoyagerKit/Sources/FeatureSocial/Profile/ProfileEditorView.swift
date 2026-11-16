import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// The lists the editor opens.
enum ProfileDestination: Hashable {
    case requests, followers, following, blocked

    var kind: ProfileListKind {
        switch self {
        case .requests: .requests
        case .followers: .followers
        case .following: .following
        case .blocked: .blocked
        }
    }
}

/// You > My profile (`router.open(.profileEditor)`): create or edit the handle, visibility, bio and the opt-ins, with the
/// community rules shown once before the first save, and the lists of follow requests, blocked people, followers and following.
public struct ProfileEditorView: View {
    @State private var model: ProfileEditorModel
    @State private var destination: ProfileDestination?
    private let env: AppEnvironment

    @MainActor public init(env: AppEnvironment) {
        self.env = env
        _model = State(initialValue: ProfileEditorModel(env: env))
    }

    @MainActor init(model: ProfileEditorModel) {
        env = model.env
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.lg) { content }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
        }
        .background(SemanticColor.surface)
        .navigationTitle(L10n.text(model.isNew ? K.social.editor.createTitle : K.social.editor.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .onChange(of: model.noticeText) { _, text in
            if let text { LiveRegion.announce(text) }
        }
        .navigationDestination(item: $destination) { target in
            ProfileListView(model: listModel(target))
        }
        .accessibilityIdentifier("profile.editor")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.social.feed.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
        case .unavailable:
            Text(verbatim: L10n.text(K.social.errors.not_found))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
        case .failed(let kind, let detail):
            ProfileFailureView(message: ErrorCopy.message(kind: kind, detail: detail), tid: "profile.retry") {
                Task { await model.load() }
            }
        case .loaded:
            if model.needsRules { rulesCard } else { form }
        }
    }

    // MARK: Form

    @ViewBuilder private var form: some View {
        Text(verbatim: L10n.text(K.social.editor.intro))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
        handleField
        visibilitySection
        bioField
        countryPicker
        showSection
        if let text = model.noticeText { noticeView(text) }
        VButton(
            model.saving ? L10n.text(K.social.editor.saving) : L10n.text(K.social.editor.save), tid: "profile.save"
        ) { Task { await model.save() } }
        .disabled(!model.canSave)
        if !model.isNew { links }
    }

    private var handleField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            label(L10n.text(K.social.editor.handle))
            TextField(
                L10n.text(K.social.editor.handle), text: Binding(get: { model.handle }, set: { model.setHandle($0) })
            )
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            #endif
            .autocorrectionDisabled()
            .frame(minHeight: 44)
            .accessibilityIdentifier("profile.handle")
            if let message = model.handleMessage {
                Text(verbatim: message)
                    .font(VFont.body(.footnote, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.handleStatus")
            }
            Text(verbatim: L10n.text(K.social.editor.handleHelp))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusColor: Color {
        switch model.handleStatus {
        case .unavailable: SemanticColor.destructive
        default: SemanticColor.text
        }
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            label(L10n.text(K.social.editor.visibility))
            ForEach(ProfileVisibility.allCases, id: \.self) { option in
                Button { model.visibility = option } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: model.visibility == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(SemanticColor.primary).accessibilityHidden(true)
                        Text(verbatim: Self.optionTitle(option)).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.visibility == option ? .isSelected : [])
                .accessibilityIdentifier("profile.visibility.\(option.rawValue)")
            }
            Text(verbatim: Self.optionNote(model.visibility))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func optionTitle(_ option: ProfileVisibility) -> String {
        switch option {
        case .private: L10n.text(K.social.editor.visibilityOption.private)
        case .followers: L10n.text(K.social.editor.visibilityOption.followers)
        case .public: L10n.text(K.social.editor.visibilityOption.public)
        }
    }

    static func optionNote(_ option: ProfileVisibility) -> String {
        switch option {
        case .private: L10n.text(K.social.editor.visibilityNote.private)
        case .followers: L10n.text(K.social.editor.visibilityNote.followers)
        case .public: L10n.text(K.social.editor.visibilityNote.public)
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            label(L10n.text(K.social.editor.bio))
            TextField(
                L10n.text(K.social.editor.bio), text: Binding(get: { model.bio }, set: { model.setBio($0) }), axis: .vertical
            )
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("profile.bio")
            Text(verbatim: L10n.text(K.social.editor.counter, ["n": String(model.bioCount), "max": String(ProfileEditorModel.maxBio)]))
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var countryPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            label(L10n.text(K.social.editor.homeCountry))
            Picker(L10n.text(K.social.editor.homeCountry), selection: $model.homeCountry) {
                // The contract cannot clear a saved country, so "Not shown" is offered only while none is saved.
                if model.original.homeCountry == nil {
                    Text(verbatim: L10n.text(K.social.editor.none)).tag(String?.none)
                }
                ForEach(CountryNames.all(), id: \.code) { country in
                    Text(verbatim: country.name).tag(String?.some(country.code))
                }
            }
            .pickerStyle(.menu)
            .tint(SemanticColor.primary)
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("profile.country")
        }
    }

    private var showSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            label(L10n.text(K.social.editor.showLegend))
            Text(verbatim: L10n.text(K.social.editor.showNote))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            VCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    toggle(K.social.editor.flag.show_avatar, "profile.showAvatar", $model.showAvatar)
                    toggle(K.social.editor.flag.show_home_country, "profile.showHomeCountry", $model.showHomeCountry)
                    toggle(K.social.editor.flag.show_countries, "profile.showCountries", $model.showCountries)
                    if model.showsGameFields {
                        toggle(K.social.editor.flag.show_level, "profile.showLevel", $model.showLevel)
                        toggle(K.social.editor.flag.show_badges, "profile.showBadges", $model.showBadges)
                        toggle(K.social.editor.flag.leaderboard_opt_in, "profile.leaderboard", $model.leaderboardOptIn)
                    }
                }
            }
        }
    }

    private func toggle(_ key: LKey, _ tid: String, _ isOn: Binding<Bool>) -> some View {
        ProfileToggleRow(title: L10n.text(key), tid: tid, isOn: isOn)
    }

    private func noticeView(_ text: String) -> some View {
        let isError: Bool
        if case .failed = model.notice { isError = true } else { isError = false }
        return Text(verbatim: text)
            .font(VFont.body(.footnote, weight: .semibold))
            .foregroundStyle(isError ? SemanticColor.destructive : SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("profile.notice")
    }

    private var links: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                linkRow(L10n.text(K.social.editor.requests), detail: model.requestCount.map(String.init), tid: "profile.requests") {
                    destination = .requests
                }
                linkRow(L10n.text(K.social.profile.followers), detail: nil, tid: "profile.followers") { destination = .followers }
                linkRow(L10n.text(K.social.profile.followingLabel), detail: nil, tid: "profile.following") { destination = .following }
                linkRow(L10n.text(K.social.editor.blocked), detail: nil, tid: "profile.blocked") { destination = .blocked }
                if let own = model.original.handle {
                    linkRow(L10n.text(K.social.profile.viewOwn), detail: nil, tid: "profile.viewOwn") {
                        env.router.open(.profile(handle: own))
                    }
                }
            }
        }
    }

    private func linkRow(_ title: String, detail: String?, tid: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { ProfileLinkRow(title: title, detail: detail) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(tid)
    }

    private func listModel(_ target: ProfileDestination) -> ProfileListModel {
        ProfileListModel(env: env, kind: target.kind)
    }

    // MARK: Rules

    private var rulesCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.mobile.rules.title))
                    .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: L10n.text(K.mobile.rules.body))
                    .font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                ActionPair {
                    VButton(L10n.text(K.social.actions.cancel), tid: "profile.rules.cancel", role: .secondary) { model.declineRules() }
                } second: {
                    VButton(L10n.text(K.mobile.rules.accept), tid: "profile.rules.accept") { Task { await model.acceptRules() } }
                }
            }
        }
        .accessibilityIdentifier("profile.rules")
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text).font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            .accessibilityAddTraits(.isHeader)
    }
}
