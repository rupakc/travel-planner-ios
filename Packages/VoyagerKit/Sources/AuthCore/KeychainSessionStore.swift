import Foundation
import Security

public struct KeychainError: Error, Equatable {
    public let status: Int32
}

/// The raw Keychain operations, injectable so the store's logic is testable where the Keychain is
/// unavailable (SPM test hosts can fail with errSecMissingEntitlement, -34018).
public protocol KeychainBackend: Sendable {
    func read(service: String) -> Data?
    func write(_ data: Data, service: String) throws
    func delete(service: String)
}

public struct SecItemKeychainBackend: KeychainBackend {
    public init() {}

    private func query(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session"]
    }

    public func read(service: String) -> Data? {
        var q = query(service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    public func write(_ data: Data, service: String) throws {
        let update = SecItemUpdate(
            query(service) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = query(service)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(service: String) {
        SecItemDelete(query(service) as CFDictionary)
    }
}

public final class KeychainSessionStore: SessionStore, @unchecked Sendable {
    public static let defaultService = "io.github.rupakc.travelplanner.session"
    static let installedKey = "tp_installed"

    private let service: String
    private let backend: KeychainBackend

    /// On the first launch after an install (`tp_installed` missing) any leftover item is cleared first,
    /// because Keychain items survive an uninstall.
    public init(
        service: String = KeychainSessionStore.defaultService,
        backend: KeychainBackend = SecItemKeychainBackend(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.backend = backend
        if defaults.object(forKey: Self.installedKey) == nil {
            backend.delete(service: service)
            defaults.set(true, forKey: Self.installedKey)
        }
    }

    public func load() -> Session? {
        guard let data = backend.read(service: service) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ s: Session) throws {
        try backend.write(JSONEncoder().encode(s), service: service)
    }

    public func clear() { backend.delete(service: service) }
}
