import DesignSystem
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// My Plan: the picked items per group (each removable), the cost breakdown, the itinerary with editing, and
/// save, share link and export. A sheet on iPhone, an inspector on iPad (AppShell presents it).
public struct MyPlanView: View {
    let env: AppEnvironment
    @State private var model: MyPlanModel

    @MainActor public init(env: AppEnvironment) {
        self.env = env
        _model = State(initialValue: MyPlanModel(env: env))
    }

    public var body: some View {
        MyPlanContent(model: model)
            .telemetryScreen("/my-plan")
            .telemetryRoute("/my-plan")
    }
}

/// The screen body over a model (snapshot tests build it directly).
struct MyPlanContent: View {
    let model: MyPlanModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView { scrollContent }
            .background(SemanticColor.surface)
            .toast(Binding(get: { model.toast }, set: { model.toast = $0 }))
            .sheet(isPresented: Binding(get: { model.showingSave }, set: { model.showingSave = $0 })) {
                SaveSheet(model: model)
            }
            .accessibilityIdentifier("plan.screen")
    }

    /// Everything inside the scroll view; snapshot tests measure it to render the whole screen at its content height.
    var scrollContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            actions
            if !model.isSignedIn { signInNote }
            if model.isEmpty {
                EmptyState(icon: "checklist", title: L10n.text(K.plan.modal.empty))
            } else {
                if !model.costParts.isEmpty {
                    CostBreakdownView(
                        parts: model.costParts, total: model.total, budget: model.budget,
                        showsTransportNote: model.hasUnpricedTransport)
                }
                ForEach(model.groups) { group in
                    GroupCard(group: group) { model.remove($0) }
                }
                itinerary
            }
        }
        .padding(Spacing.lg)
        .readableWidth()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: model.displayName)
                .font(VFont.display(.title2))
                .foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            if let line = PlanPrintDocument.tripLine(model.searchData) {
                Text(verbatim: line)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.sm) {
            PlanActionButton(title: model.saveLabel, systemImage: "square.and.arrow.down", tid: "plan.save") {
                model.showingSave = true
            }
            .disabled(!model.canSave)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    ShareLinkButton(model: model).frame(maxWidth: .infinity)
                    ExportMenu(model: model).frame(maxWidth: .infinity)
                }
                VStack(spacing: Spacing.sm) {
                    ShareLinkButton(model: model)
                    ExportMenu(model: model)
                }
            }
            .disabled(model.isEmpty)
            .opacity(model.isEmpty ? 0.5 : 1)
        }
    }

    private var signInNote: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.mobile.plan.signInToSave))
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
            VButton(L10n.text(K.mobile.share.signIn), tid: "plan.signin", role: .secondary) { model.signIn() }
        }
    }

    @ViewBuilder private var itinerary: some View {
        if let data = model.itinerary {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: SectionID.itinerary.title)
                    .font(VFont.display(.headline))
                    .foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                ItinerarySectionView(data: data, ctx: model.itineraryContext(layout: sizeClass == .regular ? .regular : .compact))
            }
            .environment(\.itineraryHost, model.itineraryHost)
        }
    }
}

/// One group of picked items with a remove button per row.
private struct GroupCard: View {
    let group: PlanGroup
    let onRemove: (PlanEntry) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: group.icon)
                        .foregroundStyle(SectionAccent.color(for: group.accent))
                        .accessibilityHidden(true)
                    Text(verbatim: group.title)
                        .font(VFont.display(.headline))
                        .foregroundStyle(SemanticColor.text)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.entries) { entry in
                    row(entry)
                    if entry.id != group.entries.last?.id { Divider() }
                }
            }
        }
        .accessibilityIdentifier("plan.group.\(group.id)")
    }

    private func row(_ entry: PlanEntry) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.title)
                    .font(VFont.body(.subheadline, weight: .medium))
                    .foregroundStyle(SemanticColor.text)
                if let subtitle = entry.subtitle {
                    Text(verbatim: subtitle)
                        .font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted)
                }
                if let price = entry.price, typeSize.isAccessibilitySize {
                    priceText(price)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let price = entry.price, !typeSize.isAccessibilitySize { priceText(price) }
            Button { onRemove(entry) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(SemanticColor.textMuted)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text(K.plan.modal.delete) + ": " + entry.title)
            .accessibilityIdentifier("plan.remove.\(entry.field)")
        }
    }

    private func priceText(_ price: Double) -> some View {
        Text(verbatim: CostBreakdownView.usdUpTo2(price))
            .font(VFont.body(.subheadline, weight: .medium))
            .foregroundStyle(SemanticColor.textMuted)
            .fixedSize()
    }
}
