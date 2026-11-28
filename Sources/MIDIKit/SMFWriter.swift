import Foundation

/// A note of a standard MIDI file, in ticks.
public struct SMFNote: Equatable, Sendable {
    public var tick: Int
    public var length: Int
    public var pitch: Int
    public var velocity: Int
    public var releaseVelocity: Int
    /// 1 to 16.
    public var channel: Int

    public init(tick: Int, length: Int, pitch: Int, velocity: Int, releaseVelocity: Int = 64, channel: Int = 1) {
        self.tick = tick
        self.length = length
        self.pitch = pitch
        self.velocity = velocity
        self.releaseVelocity = releaseVelocity
        self.channel = channel
    }
}

extension SMF {
    /// Ticks per quarter note of the files `clip` writes.
    public static let clipResolution = 960

    /// A format 0 file of exactly `length` ticks. The same input gives the same bytes.
    /// Text events on the first and last tick keep silent edges when Logic Pro imports the file.
    public static func clip(
        name: String, tempo: Double, meter: Meter, length: Int,
        notes: [SMFNote], markers: [(tick: Int, name: String)] = []
    ) -> Data {
        func meta(_ type: UInt8, _ data: [UInt8]) -> [UInt8] {
            [0xFF, type] + variableLength(data.count) + data
        }
        // Order at one tick: meta events, note ends, note starts.
        var events: [(tick: Int, rank: Int, key: Int, bytes: [UInt8])] = []
        func add(_ tick: Int, _ rank: Int, _ key: Int, _ bytes: [UInt8]) {
            events.append((tick, rank, key, bytes))
        }
        let microseconds = Int((60_000_000 / tempo).rounded())
        add(0, 0, 0, meta(0x03, Array(name.utf8)))
        add(0, 0, 1, meta(0x51, bigEndian(microseconds, 3)))
        let power = UInt8(meter.denominator.trailingZeroBitCount)
        add(0, 0, 2, meta(0x58, [UInt8(meter.numerator), power, 24, 8]))
        for (index, marker) in markers.enumerated() {
            add(marker.tick, 0, 3 + index, meta(0x06, Array(marker.name.utf8)))
        }
        let edge = meta(0x01, Array(".".utf8))
        add(0, 0, Int.max, edge)
        add(max(length - 1, 0), 0, Int.max, edge)
        for note in notes {
            let channel = UInt8(note.channel - 1)
            add(note.tick, 2, note.pitch, [0x90 | channel, UInt8(note.pitch), UInt8(note.velocity)])
            add(note.tick + note.length, 1, note.pitch,
                [0x80 | channel, UInt8(note.pitch), UInt8(note.releaseVelocity)])
        }
        events.sort { ($0.tick, $0.rank, $0.key) < ($1.tick, $1.rank, $1.key) }

        var track: [UInt8] = []
        var last = 0
        for event in events {
            track += variableLength(event.tick - last) + event.bytes
            last = event.tick
        }
        track += variableLength(length - last) + [0xFF, 0x2F, 0x00]
        return file(resolution: clipResolution, track: track)
    }

    static func file(resolution: Int, track: [UInt8]) -> Data {
        let header = Array("MThd".utf8) + bigEndian(6, 4) + bigEndian(0, 2) + bigEndian(1, 2)
            + bigEndian(resolution, 2)
        return Data(header + Array("MTrk".utf8) + bigEndian(track.count, 4) + track)
    }

    static func variableLength(_ value: Int) -> [UInt8] {
        var rest = value >> 7
        var bytes = [UInt8(value & 0x7F)]
        while rest > 0 {
            bytes.insert(UInt8(rest & 0x7F | 0x80), at: 0)
            rest >>= 7
        }
        return bytes
    }

    static func bigEndian(_ value: Int, _ count: Int) -> [UInt8] {
        (0..<count).reversed().map { UInt8(value >> ($0 * 8) & 0xFF) }
    }

    /// The notes in order of start and pitch, and the number of note starts or ends without a partner.
    public func pairedNotes() -> (notes: [SMFNote], unpaired: Int) {
        struct Key: Hashable { let track, channel, pitch: Int }
        var open: [Key: [(tick: Int, velocity: Int)]] = [:]
        var notes: [SMFNote] = []
        var unpaired = 0
        // Events are stored in order of time within each track.
        for event in events where (0x80...0x9F).contains(event.bytes[0]) {
            let key = Key(track: event.track, channel: Int(event.bytes[0] & 0x0F) + 1, pitch: Int(event.bytes[1]))
            let velocity = Int(event.bytes[2])
            if event.bytes[0] >= 0x90 && velocity > 0 {
                open[key, default: []].append((event.tick, velocity))
            } else if open[key]?.isEmpty == false {
                let start = open[key]!.removeFirst()
                notes.append(SMFNote(
                    tick: start.tick, length: event.tick - start.tick, pitch: key.pitch,
                    velocity: start.velocity, releaseVelocity: velocity, channel: key.channel
                ))
            } else {
                unpaired += 1
            }
        }
        unpaired += open.values.reduce(0) { $0 + $1.count }
        notes.sort { ($0.tick, $0.pitch, $0.channel) < ($1.tick, $1.pitch, $1.channel) }
        return (notes, unpaired)
    }
}
