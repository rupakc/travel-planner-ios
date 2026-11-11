import Foundation
import Testing
@testable import AuthCore

struct KeychainSessionStoreTests {
    private let session = Session(accessToken: "abc", user: User(username: "u", email: "u@x.io"), method: .github)

    private func defaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // Logic against the injectable backend: always runs, independent of Keychain entitlements.
    @Test func test_roundTrip() throws {
        let store = KeychainSessionStore(service: "t", backend: MemoryKeychain(), defaults: defaults())
        #expect(store.load() == nil)
        try store.save(session)
        #expect(store.load() == session)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func test_freshInstallClearsLeftover() throws {
        let kc = MemoryKeychain()
        try kc.write(JSONEncoder().encode(session), service: "t")
        let d = defaults()
        let store = KeychainSessionStore(service: "t", backend: kc, defaults: d)
        #expect(store.load() == nil)
        #expect(d.object(forKey: "tp_installed") != nil)
        try store.save(session)
        #expect(KeychainSessionStore(service: "t", backend: kc, defaults: d).load() == session)
    }

    // The real Keychain path with a unique service. A host without Keychain access
    // (errSecMissingEntitlement, -34018) is recorded as a warning; the logic is covered above.
    @Test func test_realKeychainRoundTrip() throws {
        let service = "io.github.rupakc.travelplanner.tests.\(UUID().uuidString)"
        let store = KeychainSessionStore(service: service, defaults: defaults())
        defer { store.clear() }
        do {
            try store.save(session)
        } catch let e as KeychainError where e.status == -34018 {
            Issue.record("Keychain unavailable on this host (-34018); logic covered by the fake backend", severity: .warning)
            return
        }
        #expect(store.load() == session)
        var updated = session
        updated.accessToken = "def"
        try store.save(updated)
        #expect(store.load()?.accessToken == "def")
        store.clear()
        #expect(store.load() == nil)
    }
}
