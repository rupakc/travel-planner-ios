import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureSettings

@MainActor
@Suite struct SettingsPhase3to6RowsTests {
    @Test func test_rowsHiddenWithoutFlags() {
        let model = SettingsModel(env: AppEnvironment.fake())
        #expect(!model.showsNotificationSettingsRow)
        #expect(!model.showsAlertPrefsRow)
        #expect(!model.showsMySharesRow)
    }

    @Test func test_rowDestinationsOpenThroughTheRouter() {
        let env = AppEnvironment.fake()
        let model = SettingsModel(env: env)
        model.open(.notificationSettings)
        model.open(.myShares)
        model.open(.alertPrefs)
        #expect(env.recordedRoutes == [.notificationSettings, .myShares, .alertPrefs])
    }
}
