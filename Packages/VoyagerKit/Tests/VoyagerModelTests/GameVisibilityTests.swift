import Testing

@testable import VoyagerModel

@Suite struct GameVisibilityTests {
    @Test func test_unreadableIsHidden() {
        #expect(!StaticGameVisibility.unreadable.showsGame)
        #expect(!StaticGameVisibility(gameFeature: true, hideGameSetting: nil).showsGame)
        #expect(!StaticGameVisibility(gameFeature: nil, hideGameSetting: false).showsGame)
    }

    @Test func test_playDrivenTreatsAnUnreadSettingAsVisible() {
        #expect(StaticGameVisibility.playDriven(gameFeature: true, hideGameSetting: nil, hiddenByServer: false).showsGame)
        #expect(StaticGameVisibility.playDriven(gameFeature: true, hideGameSetting: false, hiddenByServer: false).showsGame)
        #expect(!StaticGameVisibility.playDriven(gameFeature: true, hideGameSetting: true, hiddenByServer: false).showsGame)
        #expect(!StaticGameVisibility.playDriven(gameFeature: true, hideGameSetting: nil, hiddenByServer: true).showsGame)
        #expect(!StaticGameVisibility.playDriven(gameFeature: false, hideGameSetting: nil, hiddenByServer: false).showsGame)
    }

    @Test func test_hiddenByFeatureOrSetting() {
        #expect(!StaticGameVisibility(gameFeature: false, hideGameSetting: false).showsGame)
        #expect(!StaticGameVisibility.hidden.showsGame)
        #expect(StaticGameVisibility.visible.showsGame)
    }
}
