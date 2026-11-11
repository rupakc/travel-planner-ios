import Testing

@testable import SectionsUI

struct SectionStatusTests {
    @Test func test_webWordsMap() {
        #expect(SectionStatus(webWord: "waiting") == .waiting)
        #expect(SectionStatus(webWord: "loading") == .loading)
        #expect(SectionStatus(webWord: "enhancing") == .enhancing)
        #expect(SectionStatus(webWord: "done") == .done)
        #expect(SectionStatus(webWord: "error") == .error(""))
        #expect(SectionStatus(webWord: "bogus") == nil)
    }

    @Test func test_sourceMapsStaticToEnhancing() {
        #expect(SectionStatus(source: "static") == .enhancing)
        #expect(SectionStatus(source: "ai") == .done)
        #expect(SectionStatus(source: nil) == .done)
    }

    @Test func test_readyAndVisible() {
        #expect(SectionStatus.done.isReady)
        #expect(SectionStatus.enhancing.isReady)
        #expect(!SectionStatus.loading.isReady)
        #expect(!SectionStatus.error("x").isReady)
        #expect(!SectionStatus.waiting.isVisible)
        #expect(SectionStatus.loading.isVisible)
        #expect(SectionStatus.error("x").isVisible)
    }
}
