import Foundation
import Testing

@testable import VoyagerModel

@Suite struct RemoteFeaturesTests {
    private func features(_ json: String) throws -> RemoteFeatures {
        let config = try JSONDecoder().decode(ClientConfig.self, from: Data(json.utf8))
        return config.remoteFeatures
    }

    @Test func test_absentFlagsAreOff() throws {
        let off = RemoteFeatures()
        #expect(try features(#"{"features": {}}"#) == off)
        #expect(try features("{}") == off)
        #expect(RemoteFeatures(config: nil) == off)
        let wrongTypes = try features(#"{"features": {"alerts_api": null, "sharing": "x", "social": [1], "apns": {}}}"#)
        #expect(wrongTypes == off)
        #expect(!off.hasAlertsV2 && !off.showsQuickWatch && !off.hasSharingV2 && !off.hasNotificationSettings && !off.serverPushLive)
    }

    @Test func test_unknownKeysIgnored() throws {
        let parsed = try features(
            #"{"features": {"alerts_api": 2, "price_alerts_v2": true, "live_prices": true, "sharing": 1, "social": 1, "play": 0, "future_thing": {"a": 1}}, "extra": 5}"#)
        #expect(parsed.alertsAPI == 2 && parsed.priceAlertsV2 && parsed.livePrices)
        #expect(parsed.sharing == 1 && parsed.social && !parsed.play && !parsed.game)
        #expect(parsed.hasAlertsV2 && parsed.showsQuickWatch && parsed.hasSharingV2)
    }

    @Test func test_quickWatchGateFollowsR3() {
        #expect(!RemoteFeatures(alertsAPI: 2, livePrices: false).showsQuickWatch)
        #expect(RemoteFeatures(alertsAPI: 2, livePrices: true).showsQuickWatch)
        #expect(RemoteFeatures(priceAlertsV2: true, livePrices: true).showsQuickWatch)
        #expect(!RemoteFeatures(alertsAPI: 1, livePrices: true).showsQuickWatch)
    }

    @Test func test_serverPushNeedsV2AndApns() {
        #expect(!RemoteFeatures(notificationsV2: true, apns: false).serverPushLive)
        #expect(!RemoteFeatures(notificationsV2: false, apns: true).serverPushLive)
        #expect(RemoteFeatures(notificationsV2: true, apns: true).serverPushLive)
    }
}
