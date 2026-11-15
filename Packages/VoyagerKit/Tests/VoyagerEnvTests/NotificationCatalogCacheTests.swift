import Foundation
import os
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@Suite struct NotificationCatalogCacheTests {
    private final class Clock: Sendable {
        private let value = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))
        var now: Date { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    private static func catalog(_ locale: AppLanguage) -> NotificationCatalog {
        NotificationCatalog(locale: locale.rawValue, templates: ["nearby_arrival": "template-\(locale.rawValue) {place}"])
    }

    private func make(
        network: FakeNotificationCatalogRepository, store: MemoryFileStore, clock: Clock
    ) -> CachedNotificationCatalogRepository {
        CachedNotificationCatalogRepository(network: network, store: store, ttl: 3600, now: { clock.now })
    }

    @Test func test_catalogCachedPerLocale() async throws {
        let network = FakeNotificationCatalogRepository()
        network.onTemplates.handler = { locale in Self.catalog(locale) }
        let store = MemoryFileStore()
        let repo = make(network: network, store: store, clock: Clock())
        #expect(try await repo.templates(locale: .es).template("nearby_arrival") == "template-es {place}")
        #expect(try await repo.templates(locale: .es).template("nearby_arrival") == "template-es {place}")
        #expect(network.onTemplates.callCount == 1)
        #expect(try await repo.templates(locale: .de).locale == "de")
        #expect(network.onTemplates.callCount == 2)
        #expect(Set(store.files.keys) == ["notification-catalog-es.json", "notification-catalog-de.json"])
    }

    @Test func test_staleCacheRefetchesAndSurvivesAFailure() async throws {
        let network = FakeNotificationCatalogRepository()
        network.onTemplates.handler = { locale in Self.catalog(locale) }
        let clock = Clock()
        let repo = make(network: network, store: MemoryFileStore(), clock: clock)
        _ = try await repo.templates(locale: .fr)
        clock.advance(7200)
        _ = try await repo.templates(locale: .fr)
        #expect(network.onTemplates.callCount == 2)
        clock.advance(7200)
        network.onTemplates.fails(URLError(.notConnectedToInternet))
        #expect(try await repo.templates(locale: .fr).locale == "fr")  // the stale one beats nothing
    }

    @Test func test_englishFallbackWhenNothingIsCached() async throws {
        let network = FakeNotificationCatalogRepository()
        network.onTemplates.fails(URLError(.notConnectedToInternet))
        let repo = make(network: network, store: MemoryFileStore(), clock: Clock())
        let fallback = try await repo.templates(locale: .hi)
        #expect(fallback == NotificationCatalog.bundledEnglish)
        #expect(fallback.render("nearby_arrival", ["place": "A", "item": "B", "minutes": "3"]) != nil)
    }

    @Test func test_corruptCacheFileIsIgnored() async throws {
        let network = FakeNotificationCatalogRepository()
        network.onTemplates.handler = { locale in Self.catalog(locale) }
        let store = MemoryFileStore(files: ["notification-catalog-zh.json": Data("not json".utf8)])
        let repo = make(network: network, store: store, clock: Clock())
        #expect(try await repo.templates(locale: .zh).locale == "zh")
        #expect(network.onTemplates.callCount == 1)
    }
}
