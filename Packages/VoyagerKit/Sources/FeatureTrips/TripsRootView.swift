import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The Trips tab: the next trip, feature tiles, quick actions and the saved plans. On iPhone a plan opens as a
/// pushed screen; on a wide iPad the list is the content column and the plan the detail column.
public struct TripsRootView: View {
    let env: AppEnvironment
    @State private var model: TripsModel
    @State private var selectedID: Int?
    @State private var toast: ToastMessage?
    private let detailModel: @MainActor (Int) -> PlanDetailModel

    @MainActor public init(env: AppEnvironment) {
        self.init(env: env, model: TripsModel(env: env))
    }

    /// `detailModel` lets tests hand the detail column a model that is already loaded.
    @MainActor init(
        env: AppEnvironment,
        model: TripsModel,
        selectedID: Int? = nil,
        detailModel: (@MainActor (Int) -> PlanDetailModel)? = nil
    ) {
        self.env = env
        _model = State(initialValue: model)
        _selectedID = State(initialValue: selectedID)
        self.detailModel = detailModel ?? { PlanDetailModel(env: env, planID: $0) }
    }

    public var body: some View {
        AdaptiveColumns {
            NavigationStack {
                home
                    .navigationDestination(item: $selectedID) { id in detail(id) }
            }
        } regular: {
            HStack(spacing: 0) {
                NavigationStack { home }
                    .frame(width: 400)
                Divider()
                NavigationStack {
                    if let selectedID {
                        detail(selectedID)
                    } else {
                        EmptyState(icon: "suitcase", title: L10n.text(K.mobile.trips.selectPlan))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task { if env.auth.session != nil { await model.load() } }
        .telemetryScreen("/trips")
        .telemetryRoute("/trips")
        .toast($toast)
        .confirmationDialog(
            L10n.text(K.plan.modal.confirmDelete, ["name": model.pendingDelete?.name ?? ""]),
            isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.cancelDelete() } }),
            titleVisibility: .visible
        ) {
            Button(L10n.text(K.plan.modal.delete), role: .destructive) {
                let id = model.pendingDelete?.id
                Task {
                    if await model.confirmDelete(), selectedID == id { selectedID = nil }
                }
            }
            Button(L10n.text(K.alerts.ui.cancel), role: .cancel) {}
        }
        .onChange(of: model.deleteFailed) { _, failed in
            guard failed else { return }
            toast = ToastMessage(L10n.text(K.errors.generic))
            model.clearDeleteFailure()
        }
    }

    private func detail(_ id: Int) -> some View {
        PlanDetailView(env: env, model: detailModel(id)) { deletedID in
            Task { await model.didDelete(id: deletedID) }
            if selectedID == deletedID { selectedID = nil }
        }
        .id(id)
    }

    // MARK: - Home

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if model.isOffline { offlineBanner }
                if env.auth.session == nil {
                    EmptyState(
                        icon: "suitcase", title: L10n.text(K.mobile.trips.signInTitle),
                        message: L10n.text(K.mobile.trips.signInBody))
                } else {
                    signedInContent
                }
            }
            .padding(Spacing.lg)
            .readableWidth()
        }
        .background(SemanticColor.surface)
        .navigationTitle(L10n.text(K.mobile.tabs.trips))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .refreshable { await model.load() }
    }

    @ViewBuilder private var signedInContent: some View {
        if let next = model.upcoming {
            UpcomingTripCard(plan: next, departure: model.departure(of: next)) { selectedID = next.id }
        }
        quickActions
        let tiles = FeatureTile.visible(in: env)
        if !tiles.isEmpty {
            sectionTitle(L10n.text(K.mobile.trips.explore))
            FeatureTiles(tiles: tiles) { env.router.open($0) }
        }
        sectionTitle(L10n.text(K.mobile.trips.savedPlans))
        plans
    }

    private var quickActions: some View {
        // Side by side when the labels fit on one line, stacked otherwise (iPhone SE, large type, long languages).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { actionButtons }
            VStack(spacing: Spacing.sm) { actionButtons }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        VButton(L10n.text(K.mobile.trips.newSearch), tid: "trips.action.search", role: .tonal, systemImage: "magnifyingglass") {
            env.router.open(.explore(.search))
        }
        VButton(L10n.text(K.common.nav.chat), tid: "trips.action.chat", role: .tonal, systemImage: "bubble.left") {
            env.router.open(.explore(.chat))
        }
        VButton(L10n.text(K.common.nav.nearby), tid: "trips.action.nearby", role: .tonal, systemImage: "location") {
            env.router.open(.nearby)
        }
    }

    @ViewBuilder private var plans: some View {
        if model.plans.isEmpty {
            if model.failed {
                ErrorState(error: model.error) { Task { await model.load() } }
            } else if model.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(Spacing.xl)
            } else {
                EmptyState(
                    icon: "tray", title: L10n.text(K.mobile.trips.noPlansTitle),
                    message: L10n.text(K.mobile.trips.noPlansBody))
            }
        } else {
            PlansList(model: model, selectedID: selectedID) { selectedID = $0 }
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "wifi.slash").accessibilityHidden(true)
            Text(verbatim: L10n.text(K.mobile.offline.banner))
                .font(VFont.body(.footnote))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SemanticColor.text)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.itemCard))
        .overlay { RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border) }
        .accessibilityIdentifier("trips.offline")
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(verbatim: text)
            .font(VFont.display(.headline))
            .foregroundStyle(SemanticColor.text)
            .accessibilityAddTraits(.isHeader)
    }
}
