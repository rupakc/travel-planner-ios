import Foundation
import Networking
import Testing
import TestSupport
import VoyagerData
import VoyagerEnv
import VoyagerModel

@MainActor
@Suite struct NotificationSettingsServiceTests {
    private func config(api: Int = 1) -> ClientConfig { ClientConfig(features: ["notifications_api": .number(Double(api))]) }

    @Test func test_hiddenWithoutNotificationsApi() async {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes)  // no /config: every flag is off
        let service = NotificationSettingsService(env: env)
        #expect(!service.isAvailable)
        await #expect(throws: NotificationSettingsService.Unavailable.self) { try await service.settings() }
        await #expect(throws: NotificationSettingsService.Unavailable.self) {
            try await service.update(NotificationSettingsPatch(dailyCap: 4))
        }
        #expect(fakes.notificationSettings.onGet.callCount == 0 && fakes.notificationSettings.onUpdate.callCount == 0)
        let zero = AppEnvironment.fake(fakes: fakes, clientConfig: config(api: 0))
        #expect(!NotificationSettingsService(env: zero).isAvailable)
    }

    @Test func test_settingsRoundTrip() async throws {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(NotificationSettings(dailyCap: 3, timezone: "Asia/Kolkata"))
        fakes.notificationSettings.onUpdate.returns(NotificationSettings(dailyCap: 6, timezone: "Asia/Kolkata"))
        let service = NotificationSettingsService(env: AppEnvironment.fake(fakes: fakes, clientConfig: config()))
        #expect(service.isAvailable)
        #expect(try await service.settings().dailyCap == 3)
        let patch = NotificationSettingsPatch(dailyCap: 6)
        #expect(try await service.update(patch).dailyCap == 6)
        #expect(fakes.notificationSettings.onUpdate.lastCall == patch)
    }

    @Test func test_invalidPatchNeverReachesTheServer() async {
        let fakes = FakeRepositories()
        let service = NotificationSettingsService(env: AppEnvironment.fake(fakes: fakes, clientConfig: config()))
        do {
            _ = try await service.update(NotificationSettingsPatch(dailyCap: 11))
            Issue.record("expected a 422")
        } catch let error as APIError {
            #expect(NotificationSettingsFailure.from(error) == .invalid)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(fakes.notificationSettings.onUpdate.callCount == 0)
    }

    @Test func test_routeMissingTurnsTheFeatureOffForTheSession() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.fails(APIError.notFound("Not Found"))
        let service = NotificationSettingsService(env: AppEnvironment.fake(fakes: fakes, clientConfig: config()))
        await #expect(throws: APIError.self) { try await service.settings() }
        #expect(!service.isAvailable)
        await #expect(throws: NotificationSettingsService.Unavailable.self) { try await service.settings() }
        #expect(fakes.notificationSettings.onGet.callCount == 1)
    }
}
