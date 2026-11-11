import Foundation

public protocol SessionStore: Sendable {
    func load() -> Session?
    func save(_ s: Session) throws
    func clear()
}
