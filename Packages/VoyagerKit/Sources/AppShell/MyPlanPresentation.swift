import FeatureNearby
import FeaturePlan
import SwiftUI
import VoyagerEnv

/// `Route.myPlan`: a sheet in compact width, an inspector in regular width.
struct MyPlanPresentation: ViewModifier {
    let env: AppEnvironment
    let router: AppRouter
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var presented: Binding<Bool> {
        mainBinding(get: { router.myPlanPresented }, set: { router.myPlanPresented = $0 })
    }

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.inspector(isPresented: presented) {
                MyPlanView(env: env).inspectorColumnWidth(min: 320, ideal: 400, max: 520)
            }
        } else {
            content.sheet(isPresented: presented) {
                NavigationStack { MyPlanView(env: env) }
            }
        }
    }
}

struct NearbySheet: View {
    let env: AppEnvironment

    var body: some View {
        NearbyView(env: env)
    }
}
