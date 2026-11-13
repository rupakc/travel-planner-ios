import DesignSystem
import L10n
import Networking
import SectionsUI
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// A saved plan, read-only: the picked items per section, the itinerary snapshot, and the actions.
/// Open in My Plan hands the plan to the current-plan store and routes to My Plan, where export lives.
public struct PlanDetailView: View {
    let env: AppEnvironment
    let onDeleted: (@MainActor (Int) -> Void)?
    @State private var model: PlanDetailModel
    @State private var toast: ToastMessage?
    @Environment(\.dismiss) private var dismiss

    @MainActor public init(env: AppEnvironment, planID: Int, onDeleted: (@MainActor (Int) -> Void)? = nil) {
        self.init(env: env, model: PlanDetailModel(env: env, planID: planID), onDeleted: onDeleted)
    }

    @MainActor init(env: AppEnvironment, model: PlanDetailModel, onDeleted: (@MainActor (Int) -> Void)? = nil) {
        self.env = env
        self.onDeleted = onDeleted
        _model = State(initialValue: model)
    }

    public var body: some View {
        content
            .background(SemanticColor.surface)
            .navigationTitle(model.plan?.name ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await model.load() }
            .telemetryScreen("/plans/:id")
            .telemetryRoute("/plans/:id")
            .toast($toast)
            .confirmationDialog(
                L10n.text(K.plan.modal.confirmDelete, ["name": model.plan?.name ?? ""]),
                isPresented: $model.confirmingDelete, titleVisibility: .visible
            ) {
                Button(L10n.text(K.plan.modal.delete), role: .destructive) { Task { await confirmDelete() } }
                Button(L10n.text(K.alerts.ui.cancel), role: .cancel) {}
            }
            #if canImport(UIKit)
            .sheet(isPresented: shareSheetShown) {
                if let url = model.shareURL { ActivitySheet(items: [url]) }
            }
            #endif
            .onChange(of: model.shareFailed) { _, failed in
                guard failed else { return }
                toast = ToastMessage(L10n.text(K.plan.modal.msg.shareFailed))
                model.clearShareFailure()
            }
            .onChange(of: model.saveEditsFailed) { _, failed in
                guard failed else { return }
                toast = ToastMessage(L10n.text(K.plan.modal.msg.saveFailed))
                model.clearEditFeedback()
            }
            .onChange(of: model.editsSaved) { _, saved in
                guard saved else { return }
                toast = ToastMessage(L10n.text(K.plan.modal.msg.saved))
                model.clearEditFeedback()
            }
            .onChange(of: model.deleteFailed) { _, failed in
                guard failed else { return }
                toast = ToastMessage(L10n.text(K.errors.generic))
                model.clearDeleteFailure()
            }
    }

    private var shareSheetShown: Binding<Bool> {
        Binding(get: { model.shareURL != nil }, set: { if !$0 { model.shareURL = nil } })
    }

    private func confirmDelete() async {
        let id = model.planID
        if await model.confirmDelete() {
            onDeleted?(id)
            dismiss()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ErrorState(error: model.error) { Task { await model.load() } }
        case .loaded(let plan):
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if model.isOffline {
                        Text(verbatim: L10n.text(K.mobile.offline.banner))
                            .font(VFont.body(.footnote))
                            .foregroundStyle(SemanticColor.textMuted)
                            .accessibilityIdentifier("plan.detail.offline")
                    }
                    header(plan)
                    actions
                    if let itinerary = PlanDetailModel.itinerary(in: plan.selections) {
                        itinerarySection(itinerary, plan: plan)
                    }
                    ForEach(PlanDetailModel.blocks(for: plan.selections)) { block in
                        blockView(block)
                    }
                    if PlanDetailModel.blocks(for: plan.selections).isEmpty,
                        PlanDetailModel.itinerary(in: plan.selections) == nil {
                        Text(verbatim: L10n.text(K.plan.modal.empty))
                            .font(VFont.body(.subheadline))
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                }
                .padding(Spacing.lg)
                .readableWidth()
            }
        }
    }

    /// The saved itinerary, editable: edits wait in a draft until "Save changes" writes them to the plan.
    private func itinerarySection(_ itinerary: JSONValue, plan: SavedPlan) -> some View {
        var context = SectionContext.inert
        context.searchData = plan.searchData
        let host = ItineraryHost(
            itinerary: { [model] in PlanDetailModel.itinerary(in: model.plan?.selections ?? .null) },
            selections: { [model] in model.selections },
            setSelections: { [model] in model.setDraft($0) },
            recheck: ItineraryHost.recheck(
                agents: env.repos.agents, searchData: plan.searchData,
                message: { ($0 as? APIError)?.userFacingDetail }),
            editable: !model.isOffline)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            ItinerarySectionView(data: itinerary, ctx: context)
                .environment(\.itineraryHost, host)
            if model.hasUnsavedEdits {
                VButton(L10n.text(K.plan.modal.save), tid: "plan.detail.saveEdits", systemImage: "square.and.arrow.down") {
                    Task { await model.saveEdits() }
                }
                .disabled(model.isSavingEdits)
            }
        }
    }

    private func header(_ plan: SavedPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: plan.name)
                .font(VFont.display(.title2))
                .foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            if let line = Self.tripLine(plan.searchData) {
                Text(verbatim: line)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    /// `Origin → Destination · 1 Apr – 8 Apr` from the saved search; nil when it holds neither place.
    static func tripLine(_ search: JSONValue) -> String? {
        let origin = search["origin"].string ?? ""
        let destination = search["destination"].string ?? ""
        var parts: [String] = []
        if !destination.isEmpty { parts.append(origin.isEmpty ? destination : "\(origin) → \(destination)") }
        let calendar = Calendar.current
        let start = TripDates.date(search["departure_date"].string, calendar)
        let end = TripDates.date(search["return_date"].string, calendar)
        switch (start, end) {
        case (let start?, let end?): parts.append("\(Fmt.date(start)) – \(Fmt.date(end))")
        case (let start?, nil): parts.append(Fmt.date(start))
        default: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VButton(L10n.text(K.mobile.trips.openInMyPlan), tid: "plan.detail.open", systemImage: "tray.and.arrow.down") {
                model.openInMyPlan()
            }
            HStack(spacing: Spacing.sm) {
                VButton(L10n.text(K.plan.modal.share), tid: "plan.detail.share", role: .tonal, systemImage: "square.and.arrow.up") {
                    Task { await model.share() }
                }
                .disabled(model.isSharing)
                VButton(
                    L10n.text(K.plan.modal.delete), tid: "plan.detail.delete", role: .destructive, systemImage: "trash"
                ) { model.requestDelete() }
            }
        }
    }

    private func blockView(_ block: PlanBlock) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: block.section.title)
                    .font(VFont.display(.headline))
                    .foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: SectionItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: item.name ?? "–")
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.text)
            Spacer(minLength: Spacing.sm)
            if let price = item.priceUSD {
                Text(verbatim: Fmt.currency(price, code: "USD"))
                    .font(VFont.body(.subheadline, weight: .medium))
                    .foregroundStyle(SemanticColor.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if canImport(UIKit)
import UIKit

/// The system share sheet for the plan's public link.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
