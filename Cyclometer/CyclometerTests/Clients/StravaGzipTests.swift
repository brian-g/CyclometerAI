import Foundation
import Testing
@testable import Cyclometer

/// The gzip file Strava receives as `data_type=gpx.gz` (#627, PRD §8.12).
@Suite("StravaGzip")
struct StravaGzipTests {
    @Test("CRC-32 matches the standard check value")
    func crc32CheckValue() {
        #expect(Data("123456789".utf8).crc32 == 0xCBF4_3926)
        #expect(Data().crc32 == 0)
    }

    @Test("The gzip file has the header, inflates to the input, and its trailer carries the CRC and length")
    func gzipRoundTrip() throws {
        let input = Data(String(repeating: "<trkpt lat=\"37.87\" lon=\"-122.25\"><ele>293.0</ele></trkpt>\n", count: 500).utf8)

        let gzip = try input.gzipped()

        #expect(Array(gzip.prefix(4)) == [0x1F, 0x8B, 0x08, 0x00])
        #expect(gzip.count < input.count / 5)
        let deflated = gzip.subdata(in: 10..<(gzip.count - 8))
        #expect(try (deflated as NSData).decompressed(using: .zlib) as Data == input)
        let trailer = Array(gzip.suffix(8))
        let crc = trailer[0..<4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        let size = trailer[4..<8].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        #expect(crc == input.crc32)
        #expect(size == UInt32(input.count))
    }
}
