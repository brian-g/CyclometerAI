import Foundation

extension Data {
    /// The data as a gzip file (RFC 1952), for Strava's `data_type=gpx.gz` (PRD §8.12).
    ///
    /// Foundation's `.zlib` compression is raw DEFLATE (RFC 1951) with no container, so the gzip
    /// header and the CRC-32 and length trailer are added here.
    func gzipped() throws -> Data {
        let deflated = try (self as NSData).compressed(using: .zlib) as Data
        var gzip = Data(capacity: deflated.count + 18)
        // Magic, DEFLATE, no flags, no modification time, no extra flags, OS unknown.
        gzip.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        gzip.append(deflated)
        gzip.appendLittleEndian(crc32)
        gzip.appendLittleEndian(UInt32(truncatingIfNeeded: count))
        return gzip
    }

    /// The CRC-32 (IEEE 802.3, reflected) that gzip's trailer carries.
    var crc32: UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in self {
            crc = Self.crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crc32Table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in
            crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
    }

    private mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
