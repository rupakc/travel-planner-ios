import Foundation
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// B1: the price story load must start from the watch card while the story is still idle (the slot is an `EmptyView`
    /// until a story exists, so a `.task` on it never ran and no story was ever requested).
    @MainActor
    struct WatchCardStoryLoadTests {
        @Test func test_watchCardStartsTheStoryLoadWhileIdle() async throws {
            let fakes = FakeRepositories()
            fakes.alertsV2.onStory.returns(goodFlightStory)
            let config = ClientConfig(features: [
                "alerts_api": .number(2), "price_alerts_v2": .bool(true), "live_prices": .bool(true),
            ])
            let env = AppEnvironment.fake(fakes: fakes, clientConfig: config)
            let store = PriceStoryStore(env: env, track: { _ in })
            let row = WatchRow(fare(1, email: true))
            #expect(store.model(kind: row.kind, watchID: row.watchID).phase == .idle)

            let host = UIHostingController(
                rootView: WatchCard(row: row).environment(\.priceStories, store))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = host
            window.makeKeyAndVisible()
            for _ in 0..<200 where fakes.alertsV2.onStory.callCount == 0 {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            #expect(fakes.alertsV2.onStory.callCount >= 1)
            window.isHidden = true
        }
    }
#endif
