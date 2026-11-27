import Foundation

extension SMF {
    public static let emptyRegionResolution = 480

    /// A MIDI file Logic Pro imports as a region of `ticks` length with no notes.
    /// Text events on the first and last tick give the region its size.
    public static func emptyRegion(name: String, ticks: Int) -> Data {
        func length(_ value: Int) -> [UInt8] {
            var rest = value >> 7
            var bytes = [UInt8(value & 0x7F)]
            while rest > 0 {
                bytes.insert(UInt8(rest & 0x7F | 0x80), at: 0)
                rest >>= 7
            }
            return bytes
        }
        func bigEndian(_ value: Int, _ count: Int) -> [UInt8] {
            (0..<count).reversed().map { UInt8(value >> ($0 * 8) & 0xFF) }
        }
        let title = Array(name.utf8)
        let marker: [UInt8] = [0xFF, 0x01, 0x01, 0x2E]
        var track: [UInt8] = [0x00, 0xFF, 0x03] + length(title.count) + title
        track += [0x00] + marker
        track += length(ticks - 1) + marker
        track += [0x01, 0xFF, 0x2F, 0x00]
        let header = Array("MThd".utf8) + bigEndian(6, 4) + bigEndian(0, 2) + bigEndian(1, 2)
            + bigEndian(emptyRegionResolution, 2)
        return Data(header + Array("MTrk".utf8) + bigEndian(track.count, 4) + track)
    }
}
