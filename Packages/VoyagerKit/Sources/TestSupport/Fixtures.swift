@_exported import TestFixtures
import Foundation
import VoyagerModel

extension Fixtures {
    /// The JSON payload of every `data:` line of `sse/<name>.sse` (`name` with or without `.sse`), in order.
    /// A missing fixture or a line that is not JSON stops the test with a message naming the file.
    public static func sse(_ name: String) -> [JSONValue] {
        let path = "sse/" + (name.hasSuffix(".sse") ? name : name + ".sse")
        let lines: [String]
        do {
            lines = try sseDataLines(path)
        } catch {
            fatalError("Fixture \(path): \(error)")
        }
        return lines.map { line in
            do {
                return try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
            } catch {
                fatalError("Fixture \(path): a data line is not JSON: \(line.prefix(120))")
            }
        }
    }

    /// `json/<name>.json` (`name` with or without `.json`) as a `JSONValue`.
    public static func json(_ name: String) -> JSONValue {
        let path = "json/" + (name.hasSuffix(".json") ? name : name + ".json")
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data(path))
        } catch {
            fatalError("Fixture \(path): \(error)")
        }
    }

    /// `json/<name>.json` decoded as `T` (a model's lenient decoder).
    public static func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T {
        let path = "json/" + (name.hasSuffix(".json") ? name : name + ".json")
        do {
            return try JSONDecoder().decode(T.self, from: data(path))
        } catch {
            fatalError("Fixture \(path) as \(T.self): \(error)")
        }
    }
}
