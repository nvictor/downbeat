import Foundation

extension SMF {
    public static let emptyRegionResolution = 480

    /// A MIDI file Logic Pro imports as a region of `ticks` length with no notes.
    /// Text events on the first and last tick give the region its size.
    public static func emptyRegion(name: String, ticks: Int) -> Data {
        let title = Array(name.utf8)
        let marker: [UInt8] = [0xFF, 0x01, 0x01, 0x2E]
        var track: [UInt8] = [0x00, 0xFF, 0x03] + variableLength(title.count) + title
        track += [0x00] + marker
        track += variableLength(ticks - 1) + marker
        track += [0x01, 0xFF, 0x2F, 0x00]
        return file(resolution: emptyRegionResolution, track: track)
    }
}
