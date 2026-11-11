import Foundation
import Testing
import Telemetry

@Suite struct GzipTests {
    @Test func test_crc32KnownVector() {
        #expect(Gzip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(Gzip.crc32(Data()) == 0)
    }

    @Test func test_roundTripViaDecompress() throws {
        let input = Data(String(repeating: "{\"event\":\"ui_tap\",\"tid\":\"search.submit\"}", count: 200).utf8)
        let gz = Gzip.compress(input)
        #expect(gz.count < input.count)
        let raw = Data(gz.dropFirst(10).dropLast(8))
        let output = try (raw as NSData).decompressed(using: .zlib) as Data
        #expect(output == input)
    }

    @Test func test_headerBytes() {
        let gz = Gzip.compress(Data("hello".utf8))
        #expect(Array(gz.prefix(10)) == [0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
    }

    @Test func test_trailerHasCrcAndSizeLittleEndian() {
        let input = Data("123456789".utf8)
        let gz = Array(Gzip.compress(input).suffix(8))
        #expect(gz == [0x26, 0x39, 0xF4, 0xCB, 9, 0, 0, 0])
    }

    @Test func test_emptyInput() throws {
        let gz = Gzip.compress(Data())
        let raw = Data(gz.dropFirst(10).dropLast(8))
        let output = try (raw as NSData).decompressed(using: .zlib) as Data
        #expect(output.isEmpty)
    }
}
