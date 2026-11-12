import DesignSystem
import Domain
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

#if canImport(UIKit)
import SafariServices
#endif

/// The streamed results of one search. The model is created once per request and owned here, so rotating,
/// Split View and Slide Over resizes (a size-class change) keep the stream. iPhone: header and section cards in
/// one scroll; iPad (regular width): section index in the content column, the selected section in the detail column.
public struct ResultsView: View {
    @State private var model: ResultsModel
    @State private var collapsed: Set<SectionID> = []
    @State private var selected: SectionID?
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let env: AppEnvironment
    private let lazyStack: Bool

    @MainActor public init(env: AppEnvironment, request: TravelSearchRequest) {
        self.env = env
        lazyStack = true
        _model = State(initialValue: ResultsModel(env: env, request: request))
    }

    /// Tests and snapshots: a prepared model (and a plain stack, since lazy stacks hang hosted snapshot tests).
    @MainActor init(env: AppEnvironment, model: ResultsModel, lazyStack: Bool = false) {
        self.env = env
        self.lazyStack = lazyStack
        _model = State(initialValue: model)
    }

    public var body: some View {
        let regular = AdaptiveLayout.isRegular(sizeClass)
        let ctx = model.makeContext(layout: regular ? .regular : .compact)
        Group {
            if regular { splitLayout(ctx) } else { phoneLayout(ctx) }
        }
        .background(SemanticColor.surface)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { planButton }
        }
        .toast($model.toast)
        #if canImport(UIKit)
        .fullScreenCover(item: safariBinding) { item in
            SafariCover(url: item.url).ignoresSafeArea()
        }
        #endif
        .telemetryRoute("/results")
        .onAppear { model.start() }
        .onDisappear { model.cancel() }
        .accessibilityIdentifier("results.root")
    }

    // MARK: - Layouts

    private func phoneLayout(_ ctx: SectionContext) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header(ctx)
                PlanToolsPanel(env: env, state: model.state, ctx: ctx)
                sectionsBody(ctx)
            }
            .padding(Spacing.lg)
        }
    }

    private func splitLayout(_ ctx: SectionContext) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(ctx)
                    SectionIndexList(state: model.state, selected: selectionBinding)
                }
                .padding(Spacing.lg)
            }
            .frame(width: 340)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    PlanToolsPanel(env: env, state: model.state, ctx: ctx)
                    SectionDetailColumn(state: model.state, selected: effectiveSelection, ctx: ctx)
                }
                .padding(Spacing.lg)
            }
        }
    }

    private func header(_ ctx: SectionContext) -> some View {
        ResultsHeader(
            request: model.request, state: model.state, ctx: ctx, interrupted: model.interrupted, failure: model.failureMessage)
    }

    @ViewBuilder private func sectionsBody(_ ctx: SectionContext) -> some View {
        if let pricing = model.state.pricing {
            PricingAdvisorView(data: pricing, ctx: ctx)
        }
        SectionsList(state: model.state, ctx: ctx, lazy: lazyStack, collapsed: $collapsed)
    }

    // MARK: - Selection and toolbar

    private var effectiveSelection: SectionID? { selected ?? model.state.visibleSections.first }

    private var selectionBinding: Binding<SectionID?> {
        Binding(get: { effectiveSelection }, set: { selected = $0 })
    }

    private var planButton: some View {
        let count = Selections.count(env.plan.selections)
        return Button {
            env.router.open(.myPlan)
        } label: {
            Label {
                Text(verbatim: count > 0 ? "\(L10n.text(K.sections.drawer.title)) (\(count))" : L10n.text(K.sections.drawer.title))
            } icon: {
                Image(systemName: "list.bullet.clipboard")
            }
        }
        .accessibilityIdentifier("results.myPlan")
    }

    #if canImport(UIKit)
    private var safariBinding: Binding<SafariItem?> {
        Binding(
            get: { model.safariURL.map(SafariItem.init) },
            set: { if $0 == nil { model.safariURL = nil } })
    }
    #endif
}

#if canImport(UIKit)
private struct SafariItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct SafariCover: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(SemanticColor.primary)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
