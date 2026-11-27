import AudioToolbox
import Foundation

public struct MIDIError: Error, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus
    public var description: String { "\(operation) failed (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw MIDIError(operation: operation, status: status) }
}

public struct Note: Equatable, Sendable, Codable {
    public let track: Int
    /// Start position in quarter notes from the beginning of the file.
    public let beat: Double
    /// Length in quarter notes.
    public let duration: Double
    public let pitch: UInt8
    public let velocity: UInt8
    public let releaseVelocity: UInt8
    /// 1 to 16.
    public let channel: Int
}

/// A standard MIDI file backed by an AudioToolbox `MusicSequence`.
public final class MIDIFile {
    let sequence: MusicSequence

    public init(contentsOf url: URL) throws {
        var created: MusicSequence?
        try check(NewMusicSequence(&created), "NewMusicSequence")
        sequence = created!
        try check(
            MusicSequenceFileLoad(sequence, url as CFURL, .midiType, MusicSequenceLoadFlags()),
            "MusicSequenceFileLoad \(url.path)"
        )
    }

    deinit {
        DisposeMusicSequence(sequence)
    }

    public func save(to url: URL) throws {
        try check(
            MusicSequenceFileCreate(sequence, url as CFURL, .midiType, .eraseFile, try resolution()),
            "MusicSequenceFileCreate \(url.path)"
        )
    }

    /// Ticks per quarter note.
    public func resolution() throws -> Int16 {
        var tempoTrack: MusicTrack?
        try check(MusicSequenceGetTempoTrack(sequence, &tempoTrack), "MusicSequenceGetTempoTrack")
        var value: Int16 = 0
        var size = UInt32(MemoryLayout<Int16>.size)
        try check(
            MusicTrackGetProperty(tempoTrack!, kSequenceTrackProperty_TimeResolution, &value, &size),
            "MusicTrackGetProperty"
        )
        return value
    }

    public func notes() throws -> [Note] {
        var result: [Note] = []
        try forEachNote { track, beat, message, _ in
            result.append(Note(
                track: track,
                beat: beat,
                duration: Double(message.duration),
                pitch: message.note,
                velocity: message.velocity,
                releaseVelocity: message.releaseVelocity,
                channel: Int(message.channel) + 1
            ))
        }
        return result
    }

    /// Shifts every note. Throws before changing anything if a pitch would leave 0...127.
    public func transpose(semitones: Int) throws {
        let outOfRange = try notes().contains { !(0...127).contains(Int($0.pitch) + semitones) }
        guard !outOfRange else { throw TransposeError(semitones: semitones) }
        try forEachNote { _, _, message, iterator in
            var changed = message
            changed.note = UInt8(Int(message.note) + semitones)
            try check(
                MusicEventIteratorSetEventInfo(iterator, kMusicEventType_MIDINoteMessage, &changed),
                "MusicEventIteratorSetEventInfo"
            )
        }
    }

    /// Adds an empty-looking text event just before `tick`. Logic Pro ignores the
    /// end-of-track marker and sizes an imported region by its last event.
    public func extend(toTick tick: Int) throws {
        guard tick > 0 else { return }
        var track: MusicTrack?
        var count: UInt32 = 0
        try check(MusicSequenceGetTrackCount(sequence, &count), "MusicSequenceGetTrackCount")
        guard count > 0 else { return }
        try check(MusicSequenceGetIndTrack(sequence, 0, &track), "MusicSequenceGetIndTrack")

        let text = Array(".".utf8)
        let offset = MemoryLayout<MIDIMetaEvent>.offset(of: \MIDIMetaEvent.data)!
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: offset + text.count, alignment: MemoryLayout<MIDIMetaEvent>.alignment
        )
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: offset + text.count)
        let event = buffer.bindMemory(to: MIDIMetaEvent.self, capacity: 1)
        event.pointee.metaEventType = 0x01
        event.pointee.dataLength = UInt32(text.count)
        buffer.advanced(by: offset).copyMemory(from: text, byteCount: text.count)

        let beat = Double(tick - 1) / Double(try resolution())
        try check(MusicTrackNewMetaEvent(track!, beat, event), "MusicTrackNewMetaEvent")
    }

    private func forEachNote(
        _ body: (Int, MusicTimeStamp, MIDINoteMessage, MusicEventIterator) throws -> Void
    ) throws {
        var count: UInt32 = 0
        try check(MusicSequenceGetTrackCount(sequence, &count), "MusicSequenceGetTrackCount")
        for index in 0..<count {
            var track: MusicTrack?
            try check(MusicSequenceGetIndTrack(sequence, index, &track), "MusicSequenceGetIndTrack")
            try forEachEvent(in: track!) { _, beat, type, data, iterator in
                if type == kMusicEventType_MIDINoteMessage {
                    try body(Int(index), beat, data.load(as: MIDINoteMessage.self), iterator)
                }
                return false
            }
        }
    }

    /// Visits the events of a track in order. The event is deleted when `body` returns true.
    /// `position` counts the visited events, deleted ones included.
    func forEachEvent(
        in track: MusicTrack,
        _ body: (Int, MusicTimeStamp, MusicEventType, UnsafeRawPointer, MusicEventIterator) throws -> Bool
    ) throws {
        var created: MusicEventIterator?
        try check(NewMusicEventIterator(track, &created), "NewMusicEventIterator")
        let iterator = created!
        defer { DisposeMusicEventIterator(iterator) }

        var position = 0
        var hasEvent: DarwinBoolean = false
        try check(MusicEventIteratorHasCurrentEvent(iterator, &hasEvent), "MusicEventIteratorHasCurrentEvent")
        while hasEvent.boolValue {
            var beat: MusicTimeStamp = 0
            var type: MusicEventType = 0
            var data: UnsafeRawPointer?
            var size: UInt32 = 0
            try check(
                MusicEventIteratorGetEventInfo(iterator, &beat, &type, &data, &size),
                "MusicEventIteratorGetEventInfo"
            )
            if let data, try body(position, beat, type, data, iterator) {
                // Deleting moves the iterator to the next event.
                try check(MusicEventIteratorDeleteEvent(iterator), "MusicEventIteratorDeleteEvent")
            } else {
                try check(MusicEventIteratorNextEvent(iterator), "MusicEventIteratorNextEvent")
            }
            position += 1
            try check(MusicEventIteratorHasCurrentEvent(iterator, &hasEvent), "MusicEventIteratorHasCurrentEvent")
        }
    }
}

public struct TransposeError: Error, CustomStringConvertible {
    public let semitones: Int
    public var description: String {
        "transposing by \(semitones) semitones moves a note outside 0...127"
    }
}
