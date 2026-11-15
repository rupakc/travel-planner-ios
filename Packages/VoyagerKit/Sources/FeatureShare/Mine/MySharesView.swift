import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// You > Your shared links (`router.open(.myShares)`): every link the user made, newest first, then the plan links from
/// before sharing 2.0, with copy, open, share again and stop sharing, and a paste control to open a link someone sent.
public struct MySharesView: View {
    @State private var model: MySharesModel
    private let env: AppEnvironment

    @MainActor public init(env: AppEnvironment) {
        self.env = env
        _model = State(initialValue: MySharesModel(env: env))
    }

    @MainActor init(model: MySharesModel, env: AppEnvironment) {
        self.env = env
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                content
            }
            .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
        }
        .background(SemanticColor.surface)
        .navigationTitle(L10n.text(K.share.mine.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: model.noticeText) { _, text in
            if let text { LiveRegion.announce(text) }
        }
        .sheet(
            item: $model.sharingAgain, onDismiss: { Task { await model.load() } },
            content: { item in
                if let target = item.target {
                    ShareSheetView(env: env, target: target, options: item.options ?? ShareOptions())
                }
            })
        .accessibilityIdentifier("shares.root")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.share.mine.loading)) }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
                .accessibilityIdentifier("shares.loading")
        case .unavailable:
            Text(verbatim: L10n.text(K.share.errors.unavailable))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                .accessibilityIdentifier("shares.unavailable")
        case .failed(let kind, let detail):
            failure(kind: kind, detail: detail)
        case .loaded:
            loaded
        }
    }

    @ViewBuilder private var loaded: some View {
        Text(verbatim: L10n.text(K.share.mine.intro))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
        if let text = model.noticeText { notice(text) }
        if model.isEmpty {
            EmptyState(icon: "link", title: L10n.text(K.share.mine.empty))
                .accessibilityIdentifier("shares.empty")
        }
        ForEach(model.shares) { item in
            ShareRow(item: item, model: model)
        }
        if !model.legacy.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.share.mine.legacyTitle))
                    .font(VFont.body(.headline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: L10n.text(K.share.mine.legacyIntro))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Spacing.sm)
            ForEach(model.legacy) { item in
                ShareRow(item: item, model: model)
            }
        }
        pasteCard
    }

    private func notice(_ text: String) -> some View {
        let isError: Bool
        switch model.notice {
        case .copyFailed, .revokeFailed: isError = true
        default: isError = false
        }
        return Text(verbatim: text)
            .font(VFont.body(.footnote, weight: .semibold))
            .foregroundStyle(isError ? SemanticColor.destructive : SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("shares.notice")
    }

    private func failure(kind: ErrorPresentationKind, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: ErrorCopy.message(kind: kind, detail: detail))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
            VButton(L10n.text(K.alerts.ui.retry), tid: "shares.retry", role: .secondary) {
                Task { await model.load() }
            }
        }
        .accessibilityIdentifier("shares.failed")
    }

    /// "Open a link": the system paste control reads the pasteboard only when tapped, so there is no paste prompt.
    private var pasteCard: some View {
        let model = model
        return VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.mobile.share.openLinkLabel))
                    .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: L10n.text(K.mobile.share.openLinkPlaceholder))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                PasteButton(payloadType: URL.self) { urls in
                    Task { @MainActor in model.paste(urls) }
                }
                .labelStyle(.titleAndIcon)
                .frame(minHeight: 44)
                .accessibilityIdentifier("shares.paste")
                if model.pasteInvalid {
                    Text(verbatim: L10n.text(K.mobile.share.openLinkInvalid))
                        .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shares.paste-invalid")
                }
            }
        }
    }
}
