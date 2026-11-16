import DesignSystem
import FeatureDiscover
import FeatureSocial
import L10n
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// `Route.publishIdea`: the "Share to Ideas" sheet. It waits for the share sheet that opened it to close (a sheet cannot
/// present over a sibling sheet), and, like the share sheet, is hosted inside My Plan while that is up.
struct PublishPresentation: ViewModifier {
    let env: AppEnvironment
    let router: AppRouter
    let insideMyPlan: Bool

    private var presented: Binding<Bool> {
        mainBinding(
            get: { router.publishTarget != nil && router.shareTarget == nil && router.myPlanPresented == insideMyPlan },
            set: { if !$0 { router.publishTarget = nil } })
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: presented) {
            if let target = router.publishTarget {
                PublishIdeaView(env: env, planID: target.planID, kind: target.kind)
            }
        }
    }
}

/// The Discover tab: "Surprise me" and, when the backend has social, an "Ideas" segment next to it (plan ruling R12).
struct DiscoverIdeasHost: View {
    let env: AppEnvironment
    let router: AppRouter

    var body: some View {
        if env.social.isAvailable {
            VStack(spacing: 0) {
                Picker("", selection: mainBinding(get: { router.showsIdeas }, set: { router.showsIdeas = $0 })) {
                    Text(verbatim: L10n.text(K.search.modes.discover)).tag(false)
                    Text(verbatim: L10n.text(K.social.feed.title)).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
                .accessibilityIdentifier("discover.segments")
                if router.showsIdeas {
                    IdeasFeedView(env: env)
                } else {
                    DiscoverView(env: env)
                }
            }
        } else {
            DiscoverView(env: env)
        }
    }
}
