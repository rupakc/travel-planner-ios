import Foundation
import Testing
import TestFixtures
import VoyagerModel

@Suite struct JSONValueTests {
    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private func encode(_ value: JSONValue) throws -> String {
        try value.jsonString()
    }

    @Test func test_decodesNestedAndRoundTrips() throws {
        let value = try decode(#"{"a":[1,"2",null,true]}"#)
        #expect(value == .object(["a": .array([.number(1), .string("2"), .null, .bool(true)])]))
        #expect(try encode(value) == #"{"a":[1,"2",null,true]}"#)
    }

    @Test func test_encodingSortsObjectKeys() throws {
        let value: JSONValue = ["b": 1, "a": ["d": true, "c": nil], "c": "x"]
        #expect(try encode(value) == #"{"a":{"c":null,"d":true},"b":1,"c":"x"}"#)
        #expect(try value.jsonString(prettyPrinted: true).hasPrefix("{\n  \"a\""))
    }

    @Test func test_plainEncoderRoundTrips() throws {
        let value: JSONValue = ["url": "https://x.io/a", "n": 2.5, "list": [1, nil, false], "o": [:]]
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
        #expect(try value.jsonString().contains("https://x.io/a"))
    }

    @Test func test_doubleParsesNumericStrings() {
        #expect(JSONValue.string("12.5").double == 12.5)
        #expect(JSONValue.string(" 7 ").double == 7)
        #expect(JSONValue.string("1e3").double == 1000)
        #expect(JSONValue.string("0x1A").double == 26)
        #expect(JSONValue.string("").double == 0)
        #expect(JSONValue.string("x").double == nil)
        #expect(JSONValue.string("nan").double == nil)
        #expect(JSONValue.string("12px").double == nil)
        #expect(JSONValue.number(3).double == 3)
        #expect(JSONValue.bool(true).double == nil)
        #expect(JSONValue.null.double == nil)
    }

    @Test func test_intIsExactOnly() {
        #expect(JSONValue.number(3).int == 3)
        #expect(JSONValue.string("4").int == 4)
        #expect(JSONValue.number(2.5).int == nil)
        #expect(JSONValue.number(.infinity).int == nil)
    }

    @Test func test_missingKeyIsNull() throws {
        let value = try decode(#"{"a":{"b":[10,20]}}"#)
        #expect(value["missing"] == .null)
        #expect(value["missing"]["deeper"].isNull)
        #expect(value["a"]["b"][1] == .number(20))
        #expect(value["a"]["b"][5] == .null)
        #expect(value["a"]["b"][-1] == .null)
        #expect(value["a"]["b"]["key"] == .null)
        #expect(value["a"][0] == .null)
    }

    @Test func test_accessors() {
        #expect(JSONValue.string("s").string == "s")
        #expect(JSONValue.number(1).string == nil)
        #expect(JSONValue.bool(false).bool == false)
        #expect(JSONValue.array([.null]).array == [.null])
        #expect(JSONValue.object(["k": .null]).object == ["k": .null])
        #expect(JSONValue.null.isNull)
        #expect(!JSONValue.number(0).isNull)
    }

    @Test func test_isTruthyMatchesJS() {
        #expect(!JSONValue.number(0).isTruthy)
        #expect(!JSONValue.number(.nan).isTruthy)
        #expect(!JSONValue.string("").isTruthy)
        #expect(!JSONValue.null.isTruthy)
        #expect(!JSONValue.bool(false).isTruthy)
        #expect(JSONValue.array([]).isTruthy)
        #expect(JSONValue.object([:]).isTruthy)
        #expect(JSONValue.number(-1).isTruthy)
        #expect(JSONValue.string("0").isTruthy)
        #expect(JSONValue.bool(true).isTruthy)
    }

    @Test func test_decodesSearchFixtureEvents() throws {
        let lines = try Fixtures.sseDataLines("sse/search_full.sse")
        #expect(!lines.isEmpty)
        for line in lines {
            let event = try decode(line)
            #expect(event.object != nil)
        }
    }
}
