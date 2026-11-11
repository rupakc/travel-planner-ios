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
    /// Returns the OSStatus of the delete (errSecSuccess or errSecItemNotFound both mean "gone").
    @discardableResult func delete(service: String) -> Int32
}

public struct SecItemKeychainBackend: KeychainBackend {
    public init() {}

    private func query(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session"]
    }

    public func read(service: String) -> Data? {
        var request = query(service)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &out) == errSecSuccess else { return nil }
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

    @discardableResult
    public func delete(service: String) -> Int32 {
        SecItemDelete(query(service) as CFDictionary)
    }
}

public final class KeychainSessionStore: SessionStore {
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
            // Only mark the install once the leftover is really gone; otherwise retry next launch.
            let status = backend.delete(service: service)
            if status == errSecSuccess || status == errSecItemNotFound {
                defaults.set(true, forKey: Self.installedKey)
            }
        }
    }

    public func load() -> Session? {
        guard let data = backend.read(service: service) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ session: Session) throws {
        try backend.write(JSONEncoder().encode(session), service: service)
    }

    public func clear() { _ = backend.delete(service: service) }
}
