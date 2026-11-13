import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// "Share": makes (or reuses) the plan's public link, then offers it to the system share sheet.
struct ShareLinkButton: View {
    let model: MyPlanModel

    var body: some View {
        VButton(L10n.text(K.plan.modal.share), tid: "plan.share", role: .tonal, systemImage: "square.and.arrow.up") {
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
