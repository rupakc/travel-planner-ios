import Foundation
@testable import AuthCore

final class MemoryStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var s: Session?
    init(_ s: Session? = nil) { self.s = s }
    func load() -> Session? { lock.lock(); defer { lock.unlock() }; return s }
    func save(_ x: Session) throws { lock.lock(); s = x; lock.unlock() }
    func clear() { lock.lock(); s = nil; lock.unlock() }
}

final class MemoryKeychain: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    func read(service: String) -> Data? { lock.lock(); defer { lock.unlock() }; return items[service] }
    func write(_ d: Data, service: String) throws { lock.lock(); items[service] = d; lock.unlock() }
    func delete(service: String) { lock.lock(); items[service] = nil; lock.unlock() }
}

final class FakeAPI: AuthAPI, @unchecked Sendable {
    var loginResult = LoginResponse(accessToken: "tok1", user: User(username: "amy"))
    var newToken = "tok2"
    var providerResult: Result<[AuthProviderInfo], Error> = .success([])
    private let lock = NSLock()
    private var _providerCalls = 0
    var providerCalls: Int { lock.lock(); defer { lock.unlock() }; return _providerCalls }
    func login(username: String, password: String) async throws -> LoginResponse { loginResult }
    func changePassword(current: String, new: String) async throws -> String { newToken }
    func me() async throws -> User { loginResult.user }
    func providers() async throws -> [AuthProviderInfo] {
        lock.withLock { _providerCalls += 1 }
        return try providerResult.get()
    }
}

struct NotFound: Error {}
