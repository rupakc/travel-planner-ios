import Foundation
import VoyagerEnv
import VoyagerModel

/// A scripted `SharesRepository`. Create is unscripted by default (throws `notScripted`); the list defaults to empty and
/// revoke to success.
public final class FakeSharesRepository: SharesRepository {
    public let onCreate = FakeCall<ShareRequest, Share>("shares.create")
    public let onList = FakeCall<Void, ShareList>("shares.list") { _ in ShareList() }
    public let onRevoke = FakeCall<String, Void>("shares.revoke") { _ in }
    public init() {}

    public func create(_ request: ShareRequest) async throws -> Share { try await onCreate(request) }
    public func list() async throws -> ShareList { try await onList() }
    public func revoke(token: String) async throws { try await onRevoke(token) }
}

// The fake's input mirrors the protocol's three parameters.
// swiftlint:disable large_tuple

/// A `ShareCardLoading` that writes a one-pixel PNG (or fails as scripted) and records every request.
public final class FakeShareCardLoader: ShareCardLoading {
    public let onLoad = FakeCall<(url: URL, token: String, size: ShareCardSize), URL>("shareCards.load")
    public let store: ShareCardStore

    public init(store: ShareCardStore = FakeShareCardLoader.freshStore()) {
        self.store = store
        let store = store
        onLoad.handler = { input in try store.write(Self.pixel, token: input.token, size: input.size) }
    }

    public func load(_ url: URL, token: String, size: ShareCardSize) async throws -> URL {
        try await onLoad((url, token, size))
    }

    /// A private temporary directory per loader, so parallel tests never share files.
    public static func freshStore() -> ShareCardStore {
        ShareCardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("fake-cards-\(UUID().uuidString)"))
    }

    /// A valid 1x1 PNG.
    public static let pixel = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
        ?? Data()
}

// swiftlint:enable large_tuple
