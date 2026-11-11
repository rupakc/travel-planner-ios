import Foundation
import Testing
import Domain
import TestFixtures
import VoyagerModel

/// Golden fixtures of the web's plan utils (`Tests/Fixtures/golden/<module>/<case>.json` = `{fn, args, output}`),
/// plus an English translator over the vendored web catalogue so the ported sentences can be compared verbatim.
enum PlanGolden {
    struct Case: Sendable, CustomTestStringConvertible {
        let module: String
        let name: String
        let fn: String
        let args: [JSONValue]
        let output: JSONValue

        var testDescription: String { "\(module)/\(name)" }

        func arg(_ index: Int) -> JSONValue { args.indices.contains(index) ? args[index] : .null }
    }

    static let locale = Locale(identifier: "en_US")

    static func cases(_ module: String) -> [Case] {
        let dir = Fixtures.url("golden/\(module)")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.sorted().compactMap { file in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
                  let json = try? JSONDecoder().decode(JSONValue.self, from: data),
                  let fn = json["fn"].string else {
                Issue.record("golden fixture \(module)/\(file) does not decode")
                return nil
            }
            return Case(module: module, name: String(file.dropLast(5)), fn: fn, args: json["args"].array ?? [], output: json["output"])
        }
    }

    /// `ns:dotted.key` looked up in `Upstream/locales/en/<ns>.json`, `{{name}}` interpolated.
    static let english: PlanText = { key, params in
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, var node = catalogue(parts[0]) else { return key }
        for segment in parts[1].split(separator: ".") { node = node[String(segment)] }
        guard var text = node.string else { return key }
        for (name, value) in params { text = text.replacingOccurrences(of: "{{\(name)}}", with: value) }
        return text
    }

    private static func catalogue(_ namespace: String) -> JSONValue? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Upstream/locales/en/\(namespace).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
