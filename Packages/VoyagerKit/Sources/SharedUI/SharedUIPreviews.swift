import DesignSystem
import SwiftUI
import VoyagerModel

#Preview("Buttons and chips") {
    VStack(spacing: 12) {
        VButton("Search flights", tid: "preview.primary", systemImage: "airplane") {}
        VButton("Save plan", tid: "preview.secondary", role: .secondary) {}
        HStack {
            VChip(title: "Food", tid: "preview.chip.a", selected: true) {}
            VChip(title: "History", tid: "preview.chip.b", selected: false) {}
        }
        PriceText(amount: 1249.5, estimate: true)
        VerificationBadge(verification: .object(["level": .string("verified"), "label": .string("Verified")]))
        Skeleton(lines: 3)
    }
    .padding()
    .background(SemanticColor.surface)
}
