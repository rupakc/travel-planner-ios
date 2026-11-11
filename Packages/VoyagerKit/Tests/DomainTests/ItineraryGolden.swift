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

    /// Every fixture of `module`, sorted by name. A fixture that cannot be read or decoded, or lacks `fn`,
    /// is recorded as an issue, never skipped.
    static func all(_ module: String) -> [ItineraryGoldenCase] {
        let directory = Fixtures.url("golden/\(module)")
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }.sorted()
        } catch {
            Issue.record("cannot list \(directory.path): \(error)")
            return []
        }
        return names.compactMap { file in
            do {
                let data = try Data(contentsOf: directory.appendingPathComponent(file))
                let value = try JSONDecoder().decode(JSONValue.self, from: data)
                guard let fn = value["fn"].string else {
                    Issue.record("\(module)/\(file) has no fn")
                    return nil
                }
                return ItineraryGoldenCase(
                    module: module, name: String(file.dropLast(".json".count)), fn: fn,
                    args: value["args"].array ?? [], output: value["output"]
                )
            } catch {
                Issue.record("\(module)/\(file) unreadable: \(error)")
                return nil
            }
        }
    }

    /// The number of cases in `tools/golden/cases/<module>.json`, the generator's input.
    static func declaredCaseCount(_ module: String) throws -> Int {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("tools/golden/cases/\(module).json"))
        return try JSONDecoder().decode(JSONValue.self, from: data)["cases"].array?.count ?? -1
    }

    static func named(_ module: String, _ name: String) throws -> ItineraryGoldenCase {
        guard let found = all(module).first(where: { $0.name == name }) else { throw MissingCase(name: "\(module)/\(name)") }
        return found
    }
}

struct MissingCase: Error { let name: String }
