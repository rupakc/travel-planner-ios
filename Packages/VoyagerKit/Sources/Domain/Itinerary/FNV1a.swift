import Foundation

/// FNV-1a, 32-bit, over Unicode code points (the web hashes `codePointAt`, not UTF-16 units), written in
/// base 36. A short, stable fingerprint, not for security. Port of `hash` in `itineraryLayout.js`.
enum FNV1a {
    static let offsetBasis: UInt32 = 0x811c_9dc5
    static let prime: UInt32 = 0x0100_0193

    static func hash(_ text: String) -> UInt32 {
        var value = offsetBasis
        for scalar in text.unicodeScalars {
            value ^= scalar.value
            value = value &* prime
        }
        return value
    }

    /// `hash(text).toString(36)`.
    static func base36(_ text: String) -> String {
        String(hash(text), radix: 36)
    }
}
