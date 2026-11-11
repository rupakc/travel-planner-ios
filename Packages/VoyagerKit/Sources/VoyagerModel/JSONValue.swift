import Foundation

/// Any JSON value. Backend section payloads are open-ended, so features read them through this
/// type with JS-like accessors (a missing key is `.null`, never a crash).
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Accessors

extension JSONValue {
    /// The value for `key`, or `.null` when it is absent or this is not an object.
    public subscript(key: String) -> JSONValue {
        guard case .object(let object) = self else { return .null }
        return object[key] ?? .null
    }

    /// The element at `index`, or `.null` when it is out of range or this is not an array.
    public subscript(index: Int) -> JSONValue {
        guard case .array(let array) = self, array.indices.contains(index) else { return .null }
        return array[index]
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A number, or a string parsed like JS `Number(s)` (`""` is 0, `"0x1A"` is 26).
    /// `nil` for anything that would be `NaN` and for non-number, non-string values.
    public var double: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Self.jsNumber(value)
        default: return nil
        }
    }

    /// `double` when it is a whole number that fits in `Int`, otherwise `nil`.
    public var int: Int? {
        guard let value = double, value.isFinite, value.rounded(.towardZero) == value else { return nil }
        return Int(exactly: value)
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// JS truthiness: `null`, `false`, `0`, `NaN` and `""` are falsy; arrays and objects are truthy.
    public var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        case .number(let value): return value != 0 && !value.isNaN
        case .string(let value): return !value.isEmpty
        case .array, .object: return true
        }
    }

    private static func jsNumber(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return 0 }
        switch text {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        let lower = text.lowercased()
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where lower.hasPrefix(prefix) {
            let digits = lower.dropFirst(2)
            guard !digits.isEmpty, let value = UInt64(digits, radix: radix) else { return nil }
            return Double(value)
        }
        guard text.wholeMatch(of: /[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/) != nil else { return nil }
        return Double(text)
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    /// Keys are handed to the encoder in sorted order. `JSONEncoder` does not keep insertion order,
    /// so use `jsonData()` (or `.sortedKeys`) when the bytes must be deterministic.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        case .object(let object):
            var container = encoder.container(keyedBy: AnyKey.self)
            for key in object.keys.sorted() {
                try container.encode(object[key] ?? .null, forKey: AnyKey(key))
            }
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

// MARK: - Deterministic serialisation

extension JSONValue {
    /// UTF-8 JSON with every object's keys sorted and `/` unescaped (fixtures, request bodies, hashing).
    public func jsonData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
            : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// `jsonData()` as a string.
    public func jsonString(prettyPrinted: Bool = false) throws -> String {
        String(bytes: try jsonData(prettyPrinted: prettyPrinted), encoding: .utf8) ?? ""
    }
}

// MARK: - Literals (fixtures, fakes and tests)

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
