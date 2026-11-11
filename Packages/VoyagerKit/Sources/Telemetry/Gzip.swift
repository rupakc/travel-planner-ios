import Foundation

/// RFC 1952 gzip writer. Apple's `.zlib` algorithm yields raw deflate, so the header, CRC-32 and size trailer
/// are written here.
public enum Gzip {
    private static let header: [UInt8] = [0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff]

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    /// CRC-32 (IEEE 802.3), table-driven.
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    public static func compress(_ data: Data) -> Data {
        let deflated = (try? (data as NSData).compressed(using: .zlib) as Data) ?? storedDeflate(data)
        var out = Data(header)
        out.append(deflated)
        out.append(littleEndian(crc32(data)))
        out.append(littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return out
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// Valid deflate made of stored blocks; only used if the compressor itself fails.
    private static func storedDeflate(_ data: Data) -> Data {
        var out = Data()
        var offset = 0
        repeat {
            let length = min(65_535, data.count - offset)
            let final: UInt8 = offset + length >= data.count ? 1 : 0
            out.append(final)
            let len = UInt16(length)
            out.append(contentsOf: [UInt8(len & 0xFF), UInt8(len >> 8), UInt8(~len & 0xFF), UInt8(~len >> 8)])
            out.append(data[data.startIndex + offset..<data.startIndex + offset + length])
            offset += length
        } while offset < data.count
        return out
    }
}
