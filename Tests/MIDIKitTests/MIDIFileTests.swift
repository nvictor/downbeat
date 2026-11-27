import Foundation
import Testing
@testable import MIDIKit

/// Format 1, 480 ticks: a conductor track and one instrument track.
private func fixture() -> Data {
    func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let n = body.count
        return Array(type.utf8) + [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + body
    }
    let conductor: [UInt8] = [
        0x00, 0xFF, 0x51, 0x03, 0x0D, 0x42, 0x6C,  // tempo
        0x00, 0xFF, 0x58, 0x04, 0x03, 0x02, 0x18, 0x08,  // 3/4
        0x00, 0xFF, 0x2F, 0x00,
    ]
    let name = Array("Bass".utf8)
    let instrument: [UInt8] = [0x00, 0xFF, 0x03, UInt8(name.count)] + name + [
        0x00, 0xC1, 0x21,  // program change
        0x00, 0xB1, 0x01, 0x40,  // mod wheel
        0x07, 0x91, 0x3C, 0x64,  // C4 on, 7 ticks late
        0x00, 0xE1, 0x00, 0x50,  // pitch bend
        0x00, 0xD1, 0x30,  // channel pressure
        0x00, 0xA1, 0x3C, 0x22,  // poly pressure
        0x81, 0x70, 0x81, 0x3C, 0x28,  // C4 off, release 40
        0x00, 0x91, 0x40, 0x50,
        0x83, 0x60, 0x81, 0x40, 0x00,
        0x00, 0xFF, 0x2F, 0x00,
    ]
    return Data(chunk("MThd", [0, 1, 0, 2, 0x01, 0xE0]) + chunk("MTrk", conductor) + chunk("MTrk", instrument))
}

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mid")
}

private func roundTrip(_ edit: (MIDIFile) throws -> Void = { _ in }) throws -> (before: SMF, after: SMF) {
    let input = temporaryURL()
    let output = temporaryURL()
    defer {
        try? FileManager.default.removeItem(at: input)
        try? FileManager.default.removeItem(at: output)
    }
    try fixture().write(to: input)
    let file = try MIDIFile(contentsOf: input)
    try edit(file)
    try file.save(to: output)
    return (try SMF(data: fixture()), try SMF(data: Data(contentsOf: output)))
}

/// Channel events and the meta events that matter, ignoring end-of-track markers.
private func meaningful(_ smf: SMF) -> [SMFEvent] {
    smf.events
        .filter { !($0.bytes.starts(with: [0xFF, 0x2F])) }
        .sorted { ($0.track, $0.tick, $0.bytes.description) < ($1.track, $1.tick, $1.bytes.description) }
}

@Test func readsNotes() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try fixture().write(to: url)
    let notes = try MIDIFile(contentsOf: url).notes()
    #expect(notes.map(\.pitch) == [60, 64])
    #expect(notes.map(\.velocity) == [100, 80])
    #expect(notes[0].channel == 2)
    #expect(notes[0].releaseVelocity == 40)
    #expect(abs(notes[0].beat - 7.0 / 480) < 1e-9)
    #expect(abs(notes[0].duration - 0.5) < 1e-6)
}

@Test func roundTripKeepsEveryEvent() throws {
    let (before, after) = try roundTrip()
    #expect(after.ticksPerQuarter == before.ticksPerQuarter)
    #expect(meaningful(after) == meaningful(before))
}

@Test func transposeChangesOnlyPitches() throws {
    let (before, after) = try roundTrip { try $0.transpose(semitones: 2) }
    let expected = meaningful(before).map { event in
        guard [0x80, 0x90].contains(event.bytes[0] & 0xF0) else { return event }
        var bytes = event.bytes
        bytes[1] += 2
        return SMFEvent(track: event.track, tick: event.tick, bytes: bytes)
    }
    #expect(Set(meaningful(after)) == Set(expected))
    #expect(meaningful(after).count == expected.count)
}

@Test func transposeRefusesOutOfRange() throws {
    #expect(throws: TransposeError.self) {
        _ = try roundTrip { try $0.transpose(semitones: 100) }
    }
}

@Test func differencesReportsChangedEvents() throws {
    let (before, after) = try roundTrip { try $0.transpose(semitones: 1) }
    let changes = before.differences(from: after)
    #expect(changes.removed.count == 4)
    #expect(changes.added.count == 4)
    #expect(before.differences(from: before).removed.isEmpty)
}

@Test func addMarkerAddsOneTextEvent() throws {
    let (before, after) = try roundTrip { try $0.addMarker(atTick: 3839) }
    let changes = before.differences(from: after)
    #expect(changes.removed.isEmpty)
    #expect(changes.added.map(\.tick) == [3839])
    #expect(changes.added.first?.bytes == [0xFF, 0x01, 0x2E])
}

@Test func prepareForImportMarksBothEndsOnce() throws {
    let input = temporaryURL()
    let first = temporaryURL()
    let second = temporaryURL()
    defer { [input, first, second].forEach { try? FileManager.default.removeItem(at: $0) } }
    // Starts with a name only, ends with an empty stretch.
    let body: [UInt8] = [
        0x00, 0xFF, 0x03, 0x01, 0x41,
        0x83, 0x60, 0x90, 0x3C, 0x50,
        0x81, 0x70, 0x80, 0x3C, 0x40,
        0x81, 0x70, 0xFF, 0x2F, 0x00,
    ]
    let header: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
    try Data(header + Array("MTrk".utf8) + [0, 0, 0, UInt8(body.count)] + body).write(to: input)
    try MIDIFile.prepareForImport(input, to: first)
    try MIDIFile.prepareForImport(first, to: second)
    let markers = try SMF(data: Data(contentsOf: second)).events.filter { $0.bytes.starts(with: [0xFF, 0x01]) }
    #expect(markers.map(\.tick).sorted() == [0, 959])
}

@Test func setVelocityChangesEveryNote() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try fixture().write(to: url)
    let file = try MIDIFile(contentsOf: url)
    #expect(try file.setVelocity(100) == 1)
    #expect(try file.notes().map(\.velocity) == [100, 100])
    #expect(throws: LayoutError.self) { try file.setVelocity(0) }
}

@Test func quantizeMovesStartsAndKeepsTheRest() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try fixture().write(to: url)
    let file = try MIDIFile(contentsOf: url)
    let before = try file.notes()
    #expect(try file.quantize(grid: 0.25, origin: 0, end: 4) > 0)
    let after = try file.notes()
    #expect(after.map(\.pitch) == before.map(\.pitch))
    #expect(after.map(\.releaseVelocity) == before.map(\.releaseVelocity))
    #expect(after.allSatisfy { abs(($0.beat / 0.25).rounded() * 0.25 - $0.beat) < 1e-6 })
}


@Test func addNoteAddsOnlyThatNote() throws {
    let (before, after) = try roundTrip {
        try $0.addNote(pitch: 67, beat: 4, duration: 1, velocity: 90, channel: 2)
    }
    let changes = before.differences(from: after)
    #expect(changes.removed.isEmpty)
    #expect(Set(changes.added.map(\.tick)) == [1920, 2400])
    #expect(changes.added.contains { $0.bytes == [0x91, 67, 90] })
}

@Test func addNoteRefusesAnOverlap() throws {
    #expect(throws: LayoutError.self) {
        _ = try roundTrip { try $0.addNote(pitch: 60, beat: 0.25, duration: 1, velocity: 90, channel: 2) }
    }
}

@Test(arguments: [("C3", 60), ("f#3", 66), ("Bb2", 58), ("C-2", 0), ("G8", 127), ("64", 64)])
func readsPitchNames(text: String, number: Int) {
    #expect(Pitch.parse(text) == number)
}

@Test(arguments: ["H3", "C9", "G#8", "128", "C", ""])
func refusesBadPitches(text: String) {
    #expect(Pitch.parse(text) == nil)
}

@Test func listsTheChannelsInUse() throws {
    #expect(try SMF(data: fixture()).channels == [2])
    let (_, after) = try roundTrip {
        try $0.addNote(pitch: 67, beat: 4, duration: 1, velocity: 90, channel: 3)
    }
    #expect(after.channels == [2, 3])
}

@Test func deleteNoteRemovesOnlyThatNote() throws {
    let (before, after) = try roundTrip { try $0.deleteNote(id: 2) }
    let changes = before.differences(from: after)
    #expect(changes.added.count + changes.removed.count == 2)
    #expect(after.events.allSatisfy { $0.bytes.count < 2 || $0.bytes[0] & 0xE0 != 0x80 || $0.bytes[1] != 0x40 })
}

@Test func deleteNoteRefusesAnUnknownId() throws {
    #expect(throws: LayoutError.self) { _ = try roundTrip { try $0.deleteNote(id: 3) } }
}

@Test func keepBoundsSurvivesDeletingTheOuterNotes() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try fixture().write(to: url)
    let end = try SMF(data: fixture()).bounds.end
    let file = try MIDIFile(contentsOf: url)
    try file.deleteNote(id: 2)
    try file.save(to: url)
    try MIDIFile.keepBounds(of: url, start: 0, end: end)
    let smf = try SMF(data: Data(contentsOf: url))
    #expect(smf.hasSizingEvent(atTick: 0))
    #expect(smf.hasSizingEvent(atTick: end - 1))
}

@Test func updateNoteChangesOnlyTheGivenParts() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try fixture().write(to: url)
    let file = try MIDIFile(contentsOf: url)
    let before = try file.listedNotes()
    #expect(try file.updateNote(id: 1, pitch: 62))
    let after = try file.listedNotes()
    #expect(after.map(\.pitch) == [62, 64])
    #expect(after[0].beat == before[0].beat)
    #expect(after[0].duration == before[0].duration)
    #expect(after[0].velocity == before[0].velocity)
    #expect(after[0].releaseVelocity == 40)
    #expect(after[0].channel == 2)
    #expect(after[1] == before[1])
}

@Test func updateNoteReportsNoChangeAndRefusesAnOverlap() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try fixture().write(to: url)
    let file = try MIDIFile(contentsOf: url)
    #expect(try file.updateNote(id: 2, velocity: 80) == false)
    #expect(throws: LayoutError.self) { _ = try file.updateNote(id: 2, pitch: 60, beat: 0.1) }
}

@Test func exportedNotesImportWithoutChange() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try fixture().write(to: url)
    let file = try MIDIFile(contentsOf: url)
    let exported = try file.document(origin: 0)
    let reread = try NoteDocument(json: JSONEncoder().encode(exported))
    #expect(reread == exported)
    #expect(try file.replaceNotes(with: reread, origin: 0, channel: 2) == false)
}

@Test func replaceNotesKeepsTheOtherEvents() throws {
    let document = try NoteDocument(json: Data(#"{"notes": [{"pitch": 67, "beat": 1, "duration": 2}]}"#.utf8))
    let (before, after) = try roundTrip { _ = try $0.replaceNotes(with: document, origin: 0, channel: 2) }
    func others(_ smf: SMF) -> [SMFEvent] {
        meaningful(smf).filter { ![0x80, 0x90].contains($0.bytes[0] & 0xF0) }
    }
    #expect(others(after) == others(before))
    let notes = meaningful(after).filter { [0x80, 0x90].contains($0.bytes[0] & 0xF0) }
    #expect(notes.map(\.bytes) == [[0x91, 67, 100], [0x81, 67, 64]])
    #expect(notes.map(\.tick) == [480, 1440])
}

@Test(arguments: [
    "nonsense", #"{}"#, #"{"notes": [{"beat": 0, "duration": 1}]}"#,
    #"{"notes": [{"pitch": "C3", "beat": 0, "duration": 1}]}"#,
    #"{"notes": [{"pitch": 200, "beat": 0, "duration": 1}]}"#,
    #"{"notes": [{"pitch": 60, "beat": -1, "duration": 1}]}"#,
])
func refusesABadDocument(json: String) {
    #expect(throws: LayoutError.self) { try NoteDocument(json: Data(json.utf8)) }
}

@Test func emptyRegionHasItsNameAndBounds() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let data = SMF.emptyRegion(name: "Verse", ticks: 7680)
    let smf = try SMF(data: data)
    #expect(smf.bounds.start == 0)
    #expect(smf.bounds.end == 7680)
    #expect(smf.hasSizingEvent(atTick: 0))
    #expect(smf.hasSizingEvent(atTick: 7679))
    #expect(smf.events.contains { $0.bytes == [0xFF, 0x03] + Array("Verse".utf8) })
    try data.write(to: url)
    #expect(try MIDIFile(contentsOf: url).notes().isEmpty)
}

@Test func prepareForImportMovesTheRegionToTheStart() throws {
    let input = temporaryURL()
    let output = temporaryURL()
    defer { [input, output].forEach { try? FileManager.default.removeItem(at: $0) } }
    // Everything starts at tick 2880, with a time signature and tempo there.
    let body: [UInt8] = [
        0x96, 0x40, 0xFF, 0x58, 0x04, 0x06, 0x03, 0x18, 0x08,
        0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,
        0x83, 0x60, 0x90, 0x3C, 0x50,
        0x83, 0x60, 0x80, 0x3C, 0x40,
        0x00, 0xFF, 0x2F, 0x00,
    ]
    let header: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
    try Data(header + Array("MTrk".utf8) + [0, 0, 0, UInt8(body.count)] + body).write(to: input)
    try MIDIFile.prepareForImport(input, to: output)
    let smf = try SMF(data: Data(contentsOf: output))
    #expect(smf.bounds.start == 0)
    #expect(smf.bounds.end == 960)
    #expect(smf.events.filter { $0.bytes[0] & 0xE0 == 0x80 }.map(\.tick) == [480, 960])
    #expect(smf.events.contains { $0.tick == 0 && $0.bytes.starts(with: [0xFF, 0x58]) })
}
