import Foundation
import TestFixtures
import Testing
import VoyagerModel

/// One recorded call of a web util (`Tests/Fixtures/golden/<module>/<case>.json` = `{fn, args, output}`).
/// Named for the itinerary ports so the other Domain golden suites (Tasks 10, 11) keep their own helpers.
struct ItineraryGoldenCase: Sendable, CustomTestStringConvertible {
    let module: String
    let name: String
    let fn: String
    let args: [JSONValue]
    let output: JSONValue

    var testDescription: String { "\(module)/\(name)" }

    func arg(_ index: Int) -> JSONValue { args.indices.contains(index) ? args[index] : .null }

    /// Every fixture of `module`, sorted by name.
    static func all(_ module: String) -> [ItineraryGoldenCase] {
        let directory = Fixtures.url("golden/\(module)")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .sorted()
        return names.compactMap { file in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                  let fn = value["fn"].string else { return nil }
            return ItineraryGoldenCase(
                module: module, name: String(file.dropLast(".json".count)), fn: fn,
                args: value["args"].array ?? [], output: value["output"]
            )
        }
    }

    static func named(_ module: String, _ name: String) throws -> ItineraryGoldenCase {
        guard let found = all(module).first(where: { $0.name == name }) else { throw MissingCase(name: "\(module)/\(name)") }
        return found
    }
}

struct MissingCase: Error { let name: String }
