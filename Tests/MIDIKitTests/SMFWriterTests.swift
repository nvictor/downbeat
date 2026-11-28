import Foundation
import Testing
@testable import MIDIKit

private func clip() -> Data {
    SMF.clip(
        name: "08 fill a", tempo: 69, meter: .common, length: 7680,
        notes: [
            SMFNote(tick: 0, length: 120, pitch: 51, velocity: 100, releaseVelocity: 30),
            SMFNote(tick: 960, length: 120, pitch: 38, velocity: 122),
        ],
        markers: [(0, "08 fill a")]
    )
}

@Test func writesAClipOfExactLength() throws {
    let smf = try SMF(data: clip())
    #expect(smf.format == 0)
    #expect(smf.ticksPerQuarter == 960)
    // The second bar is silent.
    #expect(smf.bounds.start == 0)
    #expect(smf.bounds.end == 7680)
    let (notes, unpaired) = smf.pairedNotes()
    #expect(unpaired == 0)
    #expect(notes.map(\.pitch) == [51, 38])
    #expect(notes[0].releaseVelocity == 30)
    #expect(smf.events.contains { $0.bytes == [0xFF, 0x51, 0x0D, 0x44, 0xBD] })
    #expect(smf.events.contains { $0.bytes == [0xFF, 0x58, 4, 2, 24, 8] })
    #expect(clip() == clip())
}

@Test func writesAClipThatAudioToolboxReads() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mid")
    defer { try? FileManager.default.removeItem(at: url) }
    try clip().write(to: url)
    let notes = try MIDIFile(contentsOf: url).listedNotes()
    #expect(notes.map(\.beat) == [0, 1])
    #expect(notes.map(\.duration) == [0.125, 0.125])
}

@Test func keepsTheBytesOfAnEmptyRegion() {
    let expected: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
        + Array("MTrk".utf8) + [0, 0, 0, 20]
        + [0, 0xFF, 0x03, 1, 0x41, 0, 0xFF, 0x01, 1, 0x2E, 0x8E, 0x7F, 0xFF, 0x01, 1, 0x2E, 1, 0xFF, 0x2F, 0]
    #expect([UInt8](SMF.emptyRegion(name: "A", ticks: 1920)) == expected)
}
