import Foundation
import Testing
@testable import DownbeatKit

/// Rows as Logic Pro 13.0 reports them for an untouched region.
private let plain = [
    InspectorControl(label: "Region", value: "Expanded"),
    InspectorControl(label: "General", value: "Expanded"),
    InspectorControl(label: "Mute", value: "0"),
    InspectorControl(label: "Loop", value: "0"),
    InspectorControl(label: "Velocity Offset, 0 ", value: nil),
    InspectorControl(label: "Delay, 0 ticks", value: nil),
    InspectorControl(label: "Transpose, 0 semitones", value: nil),
    InspectorControl(label: "Pitch Source, Off, Off", value: "Off, Off"),
    InspectorControl(label: "Dynamics, 100%, 100%", value: "100%, 100%"),
    InspectorControl(label: "Gate Time, 100%, 100%", value: "100%, 100%"),
    InspectorControl(label: "Quantize", value: "Expanded"),
    InspectorControl(label: "Quantize, Off", value: nil),
]

private func replacing(_ prefix: String, with control: InspectorControl) -> [InspectorControl] {
    plain.map { $0.label.hasPrefix(prefix) && $0.label != "Quantize" ? control : $0 }
}

@Test func acceptsAnUntouchedRegion() {
    #expect(RegionSettings.problems(in: plain) == [])
}

@Test(arguments: [
    ("Loop", InspectorControl(label: "Loop", value: "1")),
    ("Mute", InspectorControl(label: "Mute", value: "1")),
    ("Velocity", InspectorControl(label: "Velocity Offset, 10 ", value: nil)),
    ("Transpose", InspectorControl(label: "Transpose, 5 semitones", value: nil)),
    ("Quantize, ", InspectorControl(label: "Quantize, 1/2 Note", value: nil)),
    ("Delay", InspectorControl(label: "Delay, 12 ticks", value: nil)),
    ("Gate", InspectorControl(label: "Gate Time, 50%, 50%", value: nil)),
])
func reportsASetting(prefix: String, control: InspectorControl) {
    #expect(RegionSettings.problems(in: replacing(prefix, with: control)).count == 1)
}

@Test func refusesWhenARequiredRowIsMissing() {
    let controls = plain.filter { $0.label != "Loop" }
    #expect(RegionSettings.problems(in: controls) == ["Loop could not be read"])
}

@Test func matchesRegionsByEveryGivenPart() {
    let parts = LogicApp.trackParts("Track 2 “Lead Guitar”")
    #expect(parts.number == 2)
    #expect(parts.name == "Lead Guitar")
    let region = RegionSummary(
        track: "Lead Guitar", trackNumber: 2, name: "Verse", startBar: 3, endBar: 5, onBarLines: true, selected: false
    )
    #expect(region.matches(RegionReference(name: "Verse", track: "2", bar: 3)))
    #expect(region.matches(RegionReference(name: nil, track: "Lead Guitar", bar: nil)))
    #expect(!region.matches(RegionReference(name: "Verse", track: nil, bar: 7)))
}

@Test(arguments: [("a minor", "A Minor"), ("F# minor", "F♯ Minor"), ("Bb major", "B♭ Major"), ("b MAJOR", "B Major")])
func spellsKeysLikeTheMenu(input: String, title: String) throws {
    #expect(try ProjectSettings.keyTitle(input) == title)
}

@Test(arguments: ["A", "H minor", "G# major", "A dorian", ""])
func refusesUnknownKeys(input: String) {
    #expect(throws: DownbeatError.self) { try ProjectSettings.keyTitle(input) }
}

@Test func checksTempoAndSignature() {
    #expect(throws: DownbeatError.self) { try ProjectSettings.checkTempo(4) }
    #expect(throws: DownbeatError.self) { try ProjectSettings.checkSignature("9/16") }
}

@Test func copiesAProjectWithoutLeftovers() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: root) }
    let source = root.appendingPathComponent("Source.logicx")
    for path in ["Alternatives/000/Autosave", "Alternatives/000/Undo Data.nosync", "Resources"] {
        try files.createDirectory(at: source.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    let copy = root.appendingPathComponent("New/Copy.logicx")
    try NewProject.copyProject(source, to: copy)
    #expect(try files.contentsOfDirectory(atPath: copy.appendingPathComponent("Alternatives/000").path) == [])
    #expect(files.fileExists(atPath: copy.appendingPathComponent("Resources").path))
    #expect(throws: DownbeatError.self) { try NewProject.copyProject(source, to: copy) }
}

@Test func comparesSettingsWithProjectMetadata() throws {
    var project = NewProject(
        destination: URL(fileURLWithPath: "/tmp/a.logicx"), template: URL(fileURLWithPath: "/tmp/b.logicx"),
        tempo: 92, signature: "6/8", key: try ProjectSettings.keyTitle("f# minor")
    )
    let stored: [String: Any] = [
        "BeatsPerMinute": 92, "SongSignatureNumerator": 6, "SongSignatureDenominator": 8,
        "SongKey": "F#", "SongGenderKey": "minor",
    ]
    #expect(project.matches(stored))
    project.key = "D Minor"
    #expect(!project.matches(stored))
}
