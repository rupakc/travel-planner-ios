import Foundation
import Testing
import TestFixtures
import VoyagerModel
@testable import Networking

struct SSEParserTests {
    private func parse(_ text: String) -> [String] {
        var parser = SSEParser()
        var out = parser.feed(Array(text.utf8)).map(\.data)
        if let last = parser.finish() { out.append(last.data) }
        return out
    }

    @Test func test_fixtureSearchFullYieldsEveryEvent() throws {
        let data = try Fixtures.data("sse/search_full.sse")
        var parser = SSEParser()
        var messages = parser.feed(data)
        if let last = parser.finish() { messages.append(last) }
        let expected = try Fixtures.sseDataLines("sse/search_full.sse")
        #expect(!expected.isEmpty)
        #expect(messages.count == expected.count)
        #expect(messages.map(\.data) == expected)
        for message in messages {
            #expect((try? JSONDecoder().decode(JSONValue.self, from: Data(message.data.utf8))) != nil)
        }
    }

    @Test func test_commentsIgnored() {
        #expect(parse(": keepalive\n\nevent: x\nid: 7\nretry: 100\ndata: {\"a\":1}\n\n: again\n\n") == ["{\"a\":1}"])
    }

    @Test func test_multiDataLinesJoined() {
        #expect(parse("data: one\ndata:two\ndata: three\n\n") == ["one\ntwo\nthree"])
    }

    @Test func test_finalEventWithoutBlankLine() {
        #expect(parse("data: a\n\ndata: b") == ["a", "b"])
        #expect(parse("data: a\n\ndata: b\n") == ["a", "b"])
    }

    @Test func test_crlfAndCR() {
        #expect(parse("data: a\r\n\r\ndata: b\r\rdata: c\n\n") == ["a", "b", "c"])
    }

    @Test func test_splitAcrossChunks() throws {
        let data = try Fixtures.data("sse/search_full.sse")
        var parser = SSEParser()
        var messages: [SSEMessage] = []
        for byte in data {
            if let message = parser.feed(byte) { messages.append(message) }
        }
        if let last = parser.finish() { messages.append(last) }
        #expect(messages.map(\.data) == (try Fixtures.sseDataLines("sse/search_full.sse")))
    }

    @Test func test_splitMultiByteCharacterAndCRLF() {
        var parser = SSEParser()
        var out: [String] = []
        // "é" (2 bytes) and a CRLF split one byte at a time
        for byte in Array("data: caf\u{E9}\r\n\r\n".utf8) {
            if let message = parser.feed(byte) { out.append(message.data) }
        }
        #expect(out == ["caf\u{E9}"])
    }
}
