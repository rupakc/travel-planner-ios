import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// "Share": makes (or reuses) the plan's public link, then offers it to the system share sheet.
struct ShareLinkButton: View {
    let model: MyPlanModel

    var body: some View {
        PlanActionButton(title: L10n.text(K.plan.modal.share), systemImage: "square.and.arrow.up", tid: "plan.share", style: .tonal) {
            Task { await model.share() }
        }
        .disabled(model.isSharing || model.isSaving)
        #if canImport(UIKit)
        .sheet(isPresented: Binding(get: { model.shareURL != nil }, set: { if !$0 { model.shareURL = nil } })) {
            if let url = model.shareURL { ActivitySheet(items: [url]).presentationDetents([.medium, .large]) }
        }
        #endif
    }
}
