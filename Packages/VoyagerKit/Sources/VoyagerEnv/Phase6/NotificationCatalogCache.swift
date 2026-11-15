import Foundation
import VoyagerModel

/// The catalog with a per-locale file cache. A fresh cached catalog (under `ttl`) is served without a request; a fetch
/// failure falls back to the stale cached one, then to the bundled English one, so this never throws. The catalog is
/// the same for every user, so it lives in Caches and is not cleared at sign-out.
public actor CachedNotificationCatalogRepository: NotificationCatalogRepository {
    /// 24 hours: the templates change only with an app or server release.
    public static let defaultTTL: TimeInterval = 24 * 3600

    private struct Entry: Codable {
        var fetchedAt: Double
        var catalog: NotificationCatalog

        enum CodingKeys: String, CodingKey {
            case fetchedAt = "fetched_at"
            case catalog
        }
    }

    private let network: any NotificationCatalogRepository
    private let store: any FileStore
    private let now: @Sendable () -> Date
    private let ttl: TimeInterval

    public init(
        network: any NotificationCatalogRepository, store: any FileStore,
        ttl: TimeInterval = CachedNotificationCatalogRepository.defaultTTL, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.network = network
        self.store = store
        self.ttl = ttl
        self.now = now
    }

    /// The live cache directory (`Library/Caches`).
    public static func cachesStore() -> DiskFileStore { DiskFileStore(root: URL.cachesDirectory) }

    static func path(for locale: AppLanguage) -> String { "notification-catalog-\(locale.rawValue).json" }

    public func templates(locale: AppLanguage) async throws -> NotificationCatalog {
        let cached = await read(locale)
        if let cached, now().timeIntervalSince1970 - cached.fetchedAt < ttl, cached.fetchedAt <= now().timeIntervalSince1970 {
            return cached.catalog
        }
        do {
            let fresh = try await network.templates(locale: locale)
            await write(Entry(fetchedAt: now().timeIntervalSince1970, catalog: fresh), locale)
            return fresh
        } catch {
            return cached?.catalog ?? .bundledEnglish
        }
    }

    private func read(_ locale: AppLanguage) async -> Entry? {
        guard let data = try? await store.read(Self.path(for: locale)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private func write(_ entry: Entry, _ locale: AppLanguage) async {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? await store.write(data, to: Self.path(for: locale))
    }
}
