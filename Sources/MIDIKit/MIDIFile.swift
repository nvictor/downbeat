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

    /// Adds one note. `beat` and `duration` are in quarter notes, `beat` from the start of the file.
    /// Throws if it would overlap a note of the same pitch and channel.
    public func addNote(pitch: Int, beat: Double, duration: Double, velocity: Int, channel: Int) throws {
        guard (0...127).contains(pitch), beat >= 0, duration > 0,
              (1...127).contains(velocity), (1...16).contains(channel) else {
            throw LayoutError(description: "the note is out of range")
        }
        let overlaps = try notes().contains {
            Int($0.pitch) == pitch && $0.channel == channel
                && $0.beat < beat + duration - 1e-6 && beat < $0.beat + $0.duration - 1e-6
        }
        guard !overlaps else {
            throw LayoutError(description: "the note overlaps another \(Pitch.name(pitch)) on channel \(channel)")
        }
        var count: UInt32 = 0
        try check(MusicSequenceGetTrackCount(sequence, &count), "MusicSequenceGetTrackCount")
        guard count > 0 else { throw LayoutError(description: "the MIDI file has no tracks") }
        var track: MusicTrack?
        try check(MusicSequenceGetIndTrack(sequence, 0, &track), "MusicSequenceGetIndTrack")
        var message = MIDINoteMessage(
            channel: UInt8(channel - 1), note: UInt8(pitch), velocity: UInt8(velocity),
            releaseVelocity: 64, duration: Float32(duration)
        )
        try check(MusicTrackNewMIDINoteEvent(track!, beat, &message), "MusicTrackNewMIDINoteEvent")
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

    /// Adds a short text event at `tick`. Logic Pro sizes an imported region by its
    /// first and last events, counting text events but not names or the end-of-track marker.
    public func addMarker(atTick tick: Int) throws {
        var track: MusicTrack?
        var count: UInt32 = 0
        try check(MusicSequenceGetTrackCount(sequence, &count), "MusicSequenceGetTrackCount")
        guard count > 0 else { throw LayoutError(description: "the MIDI file has no tracks") }
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

        let beat = Double(tick) / Double(try resolution())
        try check(MusicTrackNewMetaEvent(track!, beat, event), "MusicTrackNewMetaEvent")
    }

    /// Writes a copy of an exported region that Logic Pro imports with the same bounds.
    public static func prepareForImport(_ source: URL, to destination: URL) throws {
        let smf = try SMF(data: Data(contentsOf: source))
        let file = try MIDIFile(contentsOf: source)
        let bounds = smf.bounds
        if !smf.hasSizingEvent(atTick: bounds.start) { try file.addMarker(atTick: bounds.start) }
        if bounds.end > bounds.start, !smf.hasSizingEvent(atTick: bounds.end - 1) {
            try file.addMarker(atTick: bounds.end - 1)
        }
        try file.save(to: destination)
    }

    /// Sets the velocity of every note. Returns the number of notes changed.
    @discardableResult
    public func setVelocity(_ velocity: Int) throws -> Int {
        guard (1...127).contains(velocity) else {
            throw LayoutError(description: "velocity must be between 1 and 127")
        }
        var changed = 0
        try forEachNote { _, _, message, iterator in
            guard message.velocity != UInt8(velocity) else { return }
            var edited = message
            edited.velocity = UInt8(velocity)
            try check(
                MusicEventIteratorSetEventInfo(iterator, kMusicEventType_MIDINoteMessage, &edited),
                "MusicEventIteratorSetEventInfo"
            )
            changed += 1
        }
        return changed
    }

    /// Moves note starts to the nearest grid line, counted from `origin` (in quarter notes).
    /// Notes stay inside `origin` to `end`. Returns the number of notes changed.
    @discardableResult
    public func quantize(grid: Double, origin: Double, end: Double) throws -> Int {
        guard grid > 0 else { throw LayoutError(description: "the grid must be positive") }
        var count: UInt32 = 0
        try check(MusicSequenceGetTrackCount(sequence, &count), "MusicSequenceGetTrackCount")
        var changed = 0
        for index in 0..<count {
            var track: MusicTrack?
            try check(MusicSequenceGetIndTrack(sequence, index, &track), "MusicSequenceGetIndTrack")
            var moved: [(beat: Double, message: MIDINoteMessage)] = []
            // Moving events while iterating would reorder them, so remove and add them again.
            try forEachEvent(in: track!) { _, beat, type, data, _ in
                guard type == kMusicEventType_MIDINoteMessage else { return false }
                var message = data.load(as: MIDINoteMessage.self)
                var target = origin + ((beat - origin) / grid).rounded() * grid
                if target >= end { target -= grid }
                target = max(target, origin)
                guard abs(target - beat) > 1e-6 else { return false }
                message.duration = Float32(min(Double(message.duration), end - target))
                moved.append((target, message))
                return true
            }
            for note in moved {
                var message = note.message
                try check(MusicTrackNewMIDINoteEvent(track!, note.beat, &message), "MusicTrackNewMIDINoteEvent")
            }
            changed += moved.count
        }
        return changed
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

public struct LayoutError: Error, CustomStringConvertible {
    public let description: String
}
