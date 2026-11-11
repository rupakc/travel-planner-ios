import Foundation
import Testing
import TestFixtures
import VoyagerModel

/// One recorded web call: `fn(...args)` returned `output` (see `tools/golden/gen_golden.mjs`).
struct ExportGoldenCase: Sendable, CustomTestStringConvertible {
    let name: String
    let fn: String
    let args: [JSONValue]
    let output: JSONValue

    var testDescription: String { name }

    func arg(_ index: Int) -> JSONValue { args.indices.contains(index) ? args[index] : .null }
}

enum ExportGolden {
    /// Every case recorded under `Fixtures/golden/<directory>` (for `fn` when given), sorted by name. A fixture that
    /// cannot be listed, read or decoded, or lacks `fn`, is recorded as an issue, never skipped.
    static func cases(_ directory: String, fn wanted: String? = nil) -> [ExportGoldenCase] {
        let folder = Fixtures.url("golden/\(directory)")
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }.sorted()
        } catch {
            Issue.record("cannot list \(folder.path): \(error)")
            return []
        }
        return files.compactMap { file in
            do {
                let data = try Data(contentsOf: folder.appendingPathComponent(file))
                let json = try JSONDecoder().decode(JSONValue.self, from: data)
                guard let recorded = json["fn"].string else {
                    Issue.record("\(directory)/\(file) has no fn")
                    return nil
                }
                guard wanted == nil || wanted == recorded else { return nil }
                return ExportGoldenCase(
                    name: String(file.dropLast(".json".count)), fn: recorded, args: json["args"].array ?? [], output: json["output"])
            } catch {
                Issue.record("\(directory)/\(file) unreadable: \(error)")
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

    /// An argument `{"$date": iso}` as a `Date`.
    static func date(_ value: JSONValue) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value["$date"].string ?? "") ?? Date(timeIntervalSince1970: 0)
    }

    static var utc: TimeZone { TimeZone(secondsFromGMT: 0) ?? .gmt }
}
