import FeatureNearby
import Foundation
import NotificationsCore
import VoyagerEnv
import VoyagerModel

/// The scene-active hook of "near you" (R10). Cheap checks first (signed in, the device switch, when-in-use location
/// already allowed), then the trip phase from the saved plans, and only then `NearYouNotifier`, which reads the one
/// location and calls the non-grounded `/nearby`. It never asks for location permission (Near me does that, with
/// when-in-use only), never uses background location, and keeps nothing it reads.
@MainActor
enum NearYou {
    private static let location = CoreLocationProvider()
    private static var notifier: NearYouNotifier?

    static func sceneActive(env: AppEnvironment) async {
        guard env.auth.phase == .signedIn, env.device.nearbyInvites, location.access == .allowed else { return }
        guard let plans = try? await env.repos.plans.list() else { return }
        let phase = NearYouPhase.of(plans: plans, now: Date())
        await shared(env).evaluate(location: { await readLocation() }, phase: phase)
    }

    private static func shared(_ env: AppEnvironment) -> NearYouNotifier {
        if let notifier { return notifier }
        let made = NearYouNotifier(nearby: env.repos.nearby) { [env] in await rules(env) }
        notifier = made
        return made
    }

    /// Nil when the notification settings exist on the server but could not be read: the check waits for the next time.
    private static func rules(_ env: AppEnvironment) async -> NearYouRules? {
        let optIn = env.device.nearbyInvites
        guard RemoteFeatures(config: env.clientConfig).hasNotificationSettings else { return NearYouRules(deviceOptIn: optIn) }
        guard let settings = try? await env.repos.notificationSettings.get() else { return nil }
        return NearYouRules(deviceOptIn: optIn, settings: settings)
    }

    private static func readLocation() async -> NearYouLocation? {
        guard let here = try? await location.currentCoordinate() else { return nil }
        return NearYouLocation(lat: here.lat, lng: here.lng)
    }
}
