import Foundation
import Testing
@testable import MIDIKit

private func song(_ parts: String, extra: String = "") throws -> Arrangement {
    try Arrangement(json: Data("""
        {"version": 1, "tempo": 100, \(extra) "sections": [{"name": "a", "bars": 4, "parts": [\(parts)]}]}
        """.utf8))
}

private let groove = """
    {"bar": 1, "bars": 1, "name": "grv", "voices": [{"articulation": "kick", "gus": "P4"}],
     "notes": [{"articulation": "ride-bow", "beat": 3, "velocity": 90}]}
    """
private let copy = #"{"bar": 2, "bars": 1, "name": "grv", "use": "01 grv"}"#

private func batch(_ operations: String) throws -> EditBatch {
    try EditBatch(json: Data("{\"operations\": [\(operations)]}".utf8))
}

private func problem(_ body: () throws -> Any) -> String {
    do {
        _ = try body()
        return ""
    } catch {
        return "\(error)"
    }
}

@Test func namesThePartAndNoteOfAnUnknownArticulation() throws {
    let bad = """
        {"bar": 1, "bars": 1, "name": "grv", "notes": [{"articulation": "ride-bel", "beat": 2}]}
        """
    let message = problem { try song(bad).resolve() }
    #expect(message.hasPrefix("a / 01 grv, note 1 (beat 2): unknown articulation \"ride-bel\""))
}

@Test(arguments: [
    (#"{"bar": 4, "bars": 2, "name": "x"}"#, "ends after bar 4"),
    (#"{"bar": 1, "bars": 2, "name": "x"}, {"bar": 2, "bars": 1, "name": "y"}"#, "overlaps the part before"),
    (#"{"bar": 1, "bars": 1, "name": "x/y"}"#, "cannot be used as a file name"),
    (#"{"bar": 1, "bars": 1, "name": "x", "use": "02 y"}"#, "no part matches"),
    (#"{"bar": 1, "bars": 1, "name": "x", "notes": [{"pitch": 36, "beat": 3.9, "duration": 0.5}]}"#, "must end by beat 4"),
    (#"{"bar": 1, "bars": 1, "name": "x", "notes": [{"pitch": 36, "beat": 0, "flam": {}}]}"#, "flam starts before"),
    (#"{"bar": 1, "bars": 1, "name": "x", "notes": [{"pitch": 36, "beat": 0}, {"pitch": 36, "beat": 0}]}"#, "overlaps another"),
    (#"{"bar": 1, "bars": 1, "name": "x", "voices": [{"articulation": "kick", "gus": "P4 N(1)"}]}"#, "needs <, > or <>"),
    (#"{"bar": 1, "bars": 1, "name": "x", "colour": 1}"#, "unknown key \"colour\""),
    (#"{"bar": 1, "bars": 1, "name": "x", "notes": [{"beat": 0}]}"#, "needs either"),
])
func refusesBadParts(parts: String, expected: String) {
    #expect(problem { try song(parts).resolve() }.contains(expected))
}

@Test func laysOutOtherMeters() throws {
    let six = try song(
        #"{"bar": 2, "bars": 1, "name": "x", "voices": [{"articulation": "kick", "gus": "P6 O(2,3,5,6)"}]}"#,
        extra: #""meter": "6/8","#)
    let resolved = try six.resolve()
    #expect(resolved.sections[0].emptyBars == [1, 3, 4])
    let data = try resolved.clips(per: .section)[0].data
    let report = try MIDIReport(data: data, file: "a.mid", drumMap: six.drumMap)
    #expect(report.bars == 4)
    #expect(report.lengthBeats == 12)
    #expect(report.meter.map(\.signature) == ["6/8"])
    #expect(report.barList[1].notes.map(\.position) == [1, 4])
}

@Test func readsACustomDrumMap() throws {
    let map = #""drumMap": {"extends": "ezdrummer", "articulations": {"bell": 53}, "voices": {"ride": ["ride-bow", "bell"]}},"#
    let arrangement = try song(#"{"bar": 1, "bars": 1, "name": "x", "notes": [{"articulation": "bell", "beat": 0}]}"#, extra: map)
    #expect(try arrangement.resolve().sections[0].parts[0].hits.map(\.pitch) == [53])
    #expect(try arrangement.drumMap.expand(["ride"]) == ["ride-bow", "bell"])
    #expect(throws: LayoutError.self) { try DrumMap(articulations: ["a": 1, "b": 1]) }
}

@Test func refusesToChangeASharedGrooveSilently() throws {
    let arrangement = try song("\(groove), \(copy)")
    let operation = #"{"op": "remove", "section": "a", "bars": "2", "articulations": ["ride"]}"#
    let message = problem { try arrangement.applying(batch(operation)) }
    #expect(message.contains("Out of scope: a / 01 grv"))
}

@Test(arguments: ["source", "detach"])
func followsTheSharingChoice(shared: String) throws {
    for bar in [1, 2] {
        let operation = #"{"op": "remove", "section": "a", "bars": "\#(bar)", "articulations": ["ride"], "shared": "\#(shared)"}"#
        let (edited, report) = try song("\(groove), \(copy)").applying(batch(operation))
        let rides = try edited.resolve().sections[0].parts.map { $0.hits.filter { $0.pitch == 51 }.count }
        if shared == "source" {
            #expect(rides == [0, 0])
        } else {
            #expect(rides == (bar == 1 ? [0, 1] : [1, 0]))
            #expect(report.operations[0].parts.contains { $0.action == "detached" } == (bar == 2))
        }
        // The kick voice is not selected, so it stays written in GUS.
        #expect(edited.sections[0].parts.contains { !$0.voices.isEmpty })
        #expect(try !edited.applying(batch(operation)).report.changed)
    }
}

@Test func keepsOtherUsersTogetherWhenTheSourceChanges() throws {
    let third = #"{"bar": 3, "bars": 1, "name": "grv", "use": "01 grv"}"#
    let operation = #"{"op": "remove", "section": "a", "bars": "1", "articulations": ["ride"], "shared": "detach"}"#
    let edited = try song("\(groove), \(copy), \(third)").applying(batch(operation)).arrangement
    let parts = edited.sections[0].parts
    #expect(parts.map(\.use) == [nil, nil, "02 grv"])
    #expect(try edited.resolve().sections[0].parts.map { $0.hits.count } == [4, 5, 5])
}

@Test func copiesAVoiceAndSwapsArticulations() throws {
    let empty = #"{"bar": 2, "bars": 1, "name": "new"}"#
    let operations = """
        {"op": "copy", "section": "a", "bars": "1", "articulations": ["kick"], "to": {"section": "a", "bar": 2}},
        {"op": "replace", "section": "a", "bars": "2", "articulations": ["kick"], "with": "snare-center"}
        """
    let edited = try song("\(groove), \(empty)").applying(batch(operations)).arrangement
    let hits = try edited.resolve().sections[0].parts.map { $0.hits.map(\.pitch).sorted() }
    #expect(hits == [[36, 36, 36, 36, 51], [38, 38, 38, 38]])
}

@Test func failsTheWholeBatchOnOneBadOperation() throws {
    let operations = """
        {"op": "remove", "section": "a", "articulations": ["ride"]},
        {"op": "remove", "section": "b", "articulations": ["ride"]}
        """
    #expect(problem { try song(groove).applying(batch(operations)) }.hasPrefix("operation 2"))
}
