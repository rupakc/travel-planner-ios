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

    func arg(_ index: Int) -> JSONValue { args[index] }
}

enum ExportGolden {
    /// Every case recorded under `Fixtures/golden/<directory>`, sorted by name.
    static func cases(_ directory: String, fn: String? = nil) -> [ExportGoldenCase] {
        let folder = Fixtures.url("golden/\(directory)")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        return files.compactMap { file in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(file)),
                  let json = try? JSONDecoder().decode(JSONValue.self, from: data),
                  let recorded = json["fn"].string, fn == nil || fn == recorded else { return nil }
            return ExportGoldenCase(
                name: String(file.dropLast(5)), fn: recorded, args: json["args"].array ?? [], output: json["output"])
        }
    }

    /// An argument `{"$date": iso}` as a `Date`.
    static func date(_ value: JSONValue) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value["$date"].string ?? "") ?? Date(timeIntervalSince1970: 0)
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
