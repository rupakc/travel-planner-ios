import DesignSystem
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// The public, read-only trip page for a share link (`/share/<token>`): works signed out, like the web's
/// `SharePage`. Plan shares show their picks as read-only `SectionsUI` rows; recap and savings shares show their card.
public struct SharedPlanView: View {
    @State private var model: SharedPlanModel
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass

    @MainActor public init(env: AppEnvironment, token: String) {
        _model = State(initialValue: SharedPlanModel(env: env, token: token))
    }

    @MainActor init(model: SharedPlanModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("share.loading")
            case .notFound:
                EmptyState(
                    icon: "link.badge.plus", title: L10n.text(K.misc.share.unavailableTitle),
                    message: L10n.text(K.misc.share.unavailableBody)
                )
                .accessibilityIdentifier("share.notFound")
            case .failed(let detail, let kind):
                VStack(spacing: Spacing.md) {
                    Text(verbatim: ErrorCopy.message(kind: kind, detail: detail))
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.text)
                        .multilineTextAlignment(.center)
                    VButton(L10n.text(K.alerts.ui.retry), tid: "share.retry", role: .secondary) {
                        Task { await model.load() }
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("share.failed")
            case .loaded(let plan):
                content(plan)
            }
        }
        .background(SemanticColor.surface)
        .telemetryRoute("/share/:token")
        .task {
            if case .loading = model.state { await model.load() }
        }
        .accessibilityIdentifier("share.root")
    }

    private func content(_ plan: SharedPlan) -> some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch model.presentation {
                case .plan:
                    planBody(plan)
                case .recap:
                    SharedRecapView(
                        card: plan.card ?? SharedCard(), fallbackHeadline: model.cardHeadline ?? "", ownerName: model.ownerName,
                        onPlanOwn: planOwn)
                case .savings:
                    SharedSavingsView(
                        card: plan.card ?? SharedCard(), fallbackHeadline: model.cardHeadline ?? "", ownerName: model.ownerName,
                        onPlanOwn: planOwn)
                case .unknown:
                    SharedUnknownKindView(
                        headline: model.cardHeadline ?? L10n.text(K.misc.share.defaultDestination), ownerName: model.ownerName,
                        browserURL: model.browserURL)
                }
                Text(verbatim: L10n.text(K.misc.share.readOnly))
                    .font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.textMuted)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: AdaptiveLayout.readableMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func planBody(_ plan: SharedPlan) -> some View {
        poster(plan)
        ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
            SectionCard(id: section.id, status: .done, expanded: .constant(true)) {
                SectionRegistry.view(for: section.id, data: section.data, ctx: context)
            }
        }
        remixBar
    }

    /// "Plan your own trip": leaves the viewer for the Explore tab.
    private func planOwn() { model.planOwnTrip() }

    private var context: SectionContext {
        SectionContext(
            isSelected: { _, _ in false }, toggle: { _, _ in },
            openURL: { url, _ in if BookingLink.isAllowed(url) { openURL(url) } },
            showsVerification: false, searchData: model.plan?.searchData,
            layout: AdaptiveLayout.isRegular(sizeClass) ? .regular : .compact)
    }

    private func poster(_ plan: SharedPlan) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.misc.share.posterTag).uppercased())
                    .font(VFont.body(.caption, weight: .semibold))
                    .foregroundStyle(SemanticColor.primary)
                Text(verbatim: headline(plan))
                    .font(VFont.display(.title))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let sub = subtitle(plan) {
                    Text(verbatim: sub)
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.textMuted)
                }
                if let source = model.inspiredBy { inspired(source) }
                if let owner = model.ownerName {
                    Text(verbatim: L10n.text(K.mobile.share.byline, ["name": owner]))
                        .font(VFont.body(.footnote))
                        .foregroundStyle(SemanticColor.textMuted)
                }
            }
        }
    }

    private func headline(_ plan: SharedPlan) -> String {
        model.destination ?? model.title ?? L10n.text(K.misc.share.defaultDestination)
    }

    private func subtitle(_ plan: SharedPlan) -> String? {
        var parts: [String] = []
        if let origin = model.origin { parts.append(L10n.text(K.misc.share.fromOrigin, ["origin": origin])) }
        if let count = model.travelers { parts.append(L10n.text(K.misc.share.travelers, count: count)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func inspired(_ source: (label: String, url: URL?)) -> some View {
        let text = L10n.text(K.plan.print.inspiredBy, ["source": source.label])
        if let url = source.url {
            Button {
                openURL(url)
            } label: {
                Text(verbatim: text).underline()
            }
            .font(VFont.body(.footnote))
            .accessibilityIdentifier("share.inspiredBy")
        } else {
            Text(verbatim: text)
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
        }
    }

    private var remixBar: some View {
        VStack(spacing: Spacing.sm) {
            if model.needsSignIn {
                Text(verbatim: L10n.text(K.mobile.share.signInToRemix))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.text)
                VButton(L10n.text(K.mobile.share.signIn), tid: "share.signIn", role: .primary) { model.signIn() }
            } else {
                VButton(
                    L10n.text(K.mobile.share.remix), tid: "share.remix", role: .primary, systemImage: "arrow.triangle.branch"
                ) { model.remix() }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
