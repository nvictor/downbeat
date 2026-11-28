import Foundation
import Testing
@testable import MIDIKit

private let examples = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../../examples").standardizedFileURL

private func artemis() throws -> Arrangement {
    try Arrangement(json: Data(contentsOf: examples.appendingPathComponent("artemis.json")), directory: examples)
}

private func ride() throws -> EditBatch {
    try EditBatch(json: Data(contentsOf: examples.appendingPathComponent("artemis-ride.json")))
}

private func reports(_ arrangement: Arrangement) throws -> [String: MIDIReport] {
    let clips = try arrangement.resolve().clips(per: .section)
    return try Dictionary(uniqueKeysWithValues: clips.map {
        ($0.info.section, try MIDIReport(data: $0.data, file: $0.info.path, drumMap: arrangement.drumMap))
    })
}

/// The acceptance case: apply the ride edit, export MIDI and read it back.
@Test func keepsTheArtemisArrangementThroughExport() throws {
    let song = try reports(artemis().applying(ride()).arrangement)
    #expect(song.values.allSatisfy { $0.tempo.map(\.bpm) == [69] && $0.unpairedNotes == 0 })
    #expect(["intro", "verse", "chorus", "ending"].map { song[$0]!.bars } == [8, 16, 16, 8])
    #expect(["intro", "verse", "chorus", "ending"].map { song[$0]!.lengthBeats } == [32, 64, 64, 32])

    let chorus = song["chorus"]!.barList
    #expect(chorus[12].sameAs == 11)
    #expect(chorus[13].sameAs == 12)
    #expect(chorus[12].notes.map(\.pitch) == chorus[10].notes.map(\.pitch))

    func positions(_ bar: Int, _ name: String) -> [Double] {
        chorus[bar - 1].notes.filter { $0.articulation == name }.map(\.position)
    }
    for bar in [8, 15] {
        #expect(positions(bar, "ride-bow") == [1, 1.5, 2, 2.5, 3, 3.5])
    }
    #expect(positions(16, "ride-bow").isEmpty)
    #expect((1...7).allSatisfy { positions($0, "ride-bow").count == 8 })
    #expect(chorus.flatMap(\.notes).allSatisfy { $0.articulation?.hasPrefix("hi-hat") != true })

    let snares = song.values.flatMap(\.barList).flatMap(\.notes).filter { $0.articulation == "snare-center" }
    #expect(!snares.isEmpty)
    #expect(snares.allSatisfy { $0.flam == MIDIReport.Grace(offset: 0.0625, velocity: 44, duration: 0.025) })

    let ending = song["ending"]!.barList
    #expect(ending[2].notes.isEmpty && ending[5].notes.isEmpty)
}

@Test func editsOnlyTheNamedVoiceAndRepeatsCleanly() throws {
    let original = try artemis()
    let (edited, report) = try original.applying(ride())
    #expect(report.changed)
    let again = try edited.applying(ride())
    #expect(!again.report.changed)
    #expect(again.arrangement == edited)

    func others(_ arrangement: Arrangement) throws -> [Hit] {
        try arrangement.resolve().sections.flatMap(\.parts).flatMap(\.hits)
            .filter { !["ride-bow", "hi-hat-tight-tip", "hi-hat-tight-edge"].contains($0.articulation) }
    }
    #expect(try others(edited) == others(original))
    // The repeated groove still follows its source.
    let chorus = edited.sections.first { $0.name == "chorus" }!
    #expect(chorus.parts.first { $0.clip == "13 grv d" }?.use == "11 grv d")
}

@Test func survivesRewritingTheFile() throws {
    let original = try artemis()
    let rewritten = try Arrangement(json: original.json(), directory: examples)
    #expect(try rewritten.json() == original.json())
    let a = try original.resolve().clips(per: .part)
    let b = try rewritten.resolve().clips(per: .part)
    #expect(a.map(\.data) == b.map(\.data))
    #expect(a.map(\.info.path).contains("chorus/15 pickup.mid"))
}
