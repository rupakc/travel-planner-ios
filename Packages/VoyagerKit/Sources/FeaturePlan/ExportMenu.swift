import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry

/// Export: the calendar file (`.ics`) or the print dialog (PDF, always light).
struct ExportMenu: View {
    let model: MyPlanModel
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        Menu {
            Button {
                Telemetry.shared.track(.uiTap(tid: "plan.export.calendar", route: route))
                Task { await model.exportCalendar() }
            } label: {
                Label(L10n.text(K.plan.export.calendar), systemImage: "calendar.badge.plus")
            }
            .accessibilityIdentifier("plan.export.calendar")
            Button {
                Telemetry.shared.track(.uiTap(tid: "plan.export.print", route: route))
                model.requestPrint()
            } label: {
                Label(L10n.text(K.plan.export.print), systemImage: "printer")
            }
            .accessibilityIdentifier("plan.export.print")
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.down.doc").accessibilityHidden(true)
                Text(verbatim: L10n.text(K.mobile.plan.export))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(VFont.body(.body, weight: .semibold))
            .foregroundStyle(SemanticColor.text)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 44)
            .borderedSurface(RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
        }
        .accessibilityIdentifier("plan.export")
        #if canImport(UIKit)
        .sheet(isPresented: Binding(get: { model.calendarFile != nil }, set: { if !$0 { model.calendarFile = nil } })) {
            if let file = model.calendarFile { ActivitySheet(items: [file]).presentationDetents([.medium, .large]) }
        }
        .onChange(of: model.printRequest) { _, request in
            guard let request else { return }
            model.printRequest = nil
            if let pdf = PrintRenderer.makePDF(request.document) {
                PrintRenderer.present(pdf, jobName: request.document.name)
            }
        }
        #endif
    }
}
