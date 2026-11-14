import Testing

@testable import FeatureSocial

@Suite struct FeatureSocialTests {
    @Test func test_moduleIsLinked() {
        #expect(FeatureSocialModule.name == "social")
    }
}
