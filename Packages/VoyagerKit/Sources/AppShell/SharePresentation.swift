import FeatureShare
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// `Route.shareSheet(target)`: the share sheet (FeatureShare) over whatever is on screen. The router holds the target
/// while it is up and clears it when the sheet closes.
struct SharePresentation: ViewModifier {
    let env: AppEnvironment
    let router: AppRouter
    /// My Plan is itself a sheet (or inspector), and a sheet cannot present over a sibling sheet: while it is up the
    /// share sheet is hosted inside it, otherwise at the root.
    let insideMyPlan: Bool

    private var presented: Binding<Bool> {
        mainBinding(
            get: { router.shareTarget != nil && router.myPlanPresented == insideMyPlan },
            set: { if !$0 { router.shareTarget = nil } })
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: presented) {
            if let target = router.shareTarget {
                ShareSheetView(env: env, target: target)
            }
        }
    }
}
