import Foundation

public protocol SessionStore: Sendable {
    func load() -> Session?
    func save(_ session: Session) throws
    func clear()
}
