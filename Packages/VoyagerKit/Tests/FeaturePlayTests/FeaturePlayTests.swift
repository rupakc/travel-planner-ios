import Testing

@testable import FeaturePlay

@Suite struct FeaturePlayTests {
    @Test func test_moduleIsLinked() {
        #expect(FeaturePlayModule.name == "play")
    }
}
