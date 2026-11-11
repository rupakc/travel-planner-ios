import Foundation

/// Lenient field decoding for backend responses: an absent key, `null` or a value of the wrong
/// type is `nil` (never a thrown error), numbers may arrive as strings (`"150"`) and booleans as
/// 0/1. Unknown keys are ignored by `Decodable` itself. Required fields throw `DecodingError`.
extension KeyedDecodingContainer {
    private func raw(_ key: Key) -> JSONValue? {
        guard let value = try? decodeIfPresent(JSONValue.self, forKey: key), !value.isNull else { return nil }
        return value
    }

    func lString(_ key: Key) -> String? {
        switch raw(key) {
        case .string(let value): return value
        case .number(let value):
            return value.rounded(.towardZero) == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        default: return nil
        }
    }

    func lInt(_ key: Key) -> Int? {
        guard let value = raw(key) else { return nil }
        if case .string(let text) = value, text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return value.int
    }

    func lDouble(_ key: Key) -> Double? {
        guard let value = raw(key) else { return nil }
        if case .string(let text) = value, text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        guard let number = value.double, number.isFinite else { return nil }
        return number
    }

    func lBool(_ key: Key) -> Bool? {
        switch raw(key) {
        case .bool(let value): return value
        case .number(let value): return value == 0 ? false : (value == 1 ? true : nil)
        case .string(let text):
            switch text.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    /// Any JSON value; a missing key is `.null`.
    func lValue(_ key: Key) -> JSONValue { raw(key) ?? .null }

    /// A nested `Decodable` (struct, enum, array, dictionary); `nil` when absent or malformed.
    func lAny<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    func reqInt(_ key: Key) throws -> Int {
        guard let value = lInt(key) else { throw missing(key, "an integer") }
        return value
    }

    func reqDouble(_ key: Key) throws -> Double {
        guard let value = lDouble(key) else { throw missing(key, "a number") }
        return value
    }

    func reqString(_ key: Key) throws -> String {
        guard let value = lString(key) else { throw missing(key, "a string") }
        return value
    }

    func reqBool(_ key: Key) throws -> Bool {
        guard let value = lBool(key) else { throw missing(key, "a boolean") }
        return value
    }

    func reqAny<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
        guard let value = lAny(type, key) else { throw missing(key, "\(T.self)") }
        return value
    }

    private func missing(_ key: Key, _ expected: String) -> DecodingError {
        .keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing or invalid \(key.stringValue): expected \(expected)"))
    }
}
