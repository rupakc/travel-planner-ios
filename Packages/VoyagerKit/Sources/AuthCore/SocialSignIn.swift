import Foundation

// Phase 1 seams. Declared now with no conformers; later waves (Tasks 43-47) fill in the methods
// once the Phase 1 contract is fixed.
public protocol SignUpAPI: Sendable {}
public protocol PasswordResetAPI: Sendable {}
public protocol OAuthAPI: Sendable {}
public protocol AppleSignInAPI: Sendable {}
public protocol RefreshAPI: Sendable {}
public protocol AccountDeletionAPI: Sendable {}
