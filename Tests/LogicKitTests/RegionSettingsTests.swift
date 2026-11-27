import Testing
@testable import LogicKit

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

@Test func readsBarsFromTheHelpText() {
    let whole = "Region starts at 3 bars  and ends at 5 bars , MIDI region."
    #expect(LogicApp.bars(help: whole)?.start == 3)
    #expect(LogicApp.bars(help: whole)?.end == 5)
    #expect(LogicApp.bars(help: "Region starts at 1 bar  and ends at 2 bars , MIDI region.")?.start == 1)
    #expect(LogicApp.bars(help: "Region starts at 3 bars 3 beats  and ends at 6 bars 2 beats , MIDI region.") == nil)
}

@Test func matchesRegionsByEveryGivenPart() {
    let parts = LogicApp.trackParts("Track 2 “Lead Guitar”")
    #expect(parts.number == 2)
    #expect(parts.name == "Lead Guitar")
    let region = RegionSummary(
        track: "Lead Guitar", trackNumber: 2, name: "Verse", startBar: 3, endBar: 5, selected: false
    )
    #expect(region.matches(RegionReference(name: "Verse", track: "2", bar: 3)))
    #expect(region.matches(RegionReference(name: nil, track: "Lead Guitar", bar: nil)))
    #expect(!region.matches(RegionReference(name: "Verse", track: nil, bar: 7)))
}
