import Foundation

/// A raw event as stored in a standard MIDI file, used to compare two files without
/// going through AudioToolbox (which may drop or reorder data).
public struct SMFEvent: Equatable, Hashable, Sendable, Codable {
    public let track: Int
    public let tick: Int
    /// Status byte followed by data. Meta events are `FF type data`, without the length.
    public let bytes: [UInt8]

    public init(track: Int, tick: Int, bytes: [UInt8]) {
        self.track = track
        self.tick = tick
        self.bytes = bytes
    }
}

public struct SMF: Sendable {
    public let format: Int
    public let ticksPerQuarter: Int
    public let events: [SMFEvent]

    /// The tick of the latest end-of-track marker.
    public var endTick: Int {
        events.filter { $0.bytes.starts(with: [0xFF, 0x2F]) }.map(\.tick).max() ?? 0
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    public init(data: Data) throws {
        var reader = Reader(bytes: [UInt8](data))
        guard try reader.take(4) == Array("MThd".utf8) else { throw ParseError(description: "not a MIDI file") }
        let headerLength = try reader.integer(4)
        var header = Reader(bytes: try reader.take(headerLength))
        format = try header.integer(2)
        let trackCount = try header.integer(2)
        ticksPerQuarter = try header.integer(2)

        var events: [SMFEvent] = []
        var track = 0
        while track < trackCount {
            let kind = try reader.take(4)
            let chunk = try reader.take(try reader.integer(4))
            guard kind == Array("MTrk".utf8) else { continue }
            var body = Reader(bytes: chunk)
            var tick = 0
            var running: UInt8 = 0
            while !body.isAtEnd {
                tick += try body.variableLength()
                var status = try body.byte()
                var pending: [UInt8] = []
                if status < 0x80 {
                    guard running != 0 else { throw ParseError(description: "data byte without status") }
                    pending = [status]
                    status = running
                }
                var bytes = [status]
                switch status {
                case 0xFF:
                    bytes.append(try body.byte())
                    bytes += try body.take(try body.variableLength())
                    running = 0
                case 0xF0, 0xF7:
                    bytes += try body.take(try body.variableLength())
                    running = 0
                case 0x80...0xEF:
                    let length = (0xC0...0xDF).contains(status) ? 1 : 2
                    bytes += pending
                    bytes += try body.take(length - pending.count)
                    running = status
                default:
                    throw ParseError(description: "unsupported status byte \(status)")
                }
                events.append(SMFEvent(track: track, tick: tick, bytes: bytes))
            }
            track += 1
        }
        self.events = events
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        var isAtEnd: Bool { offset >= bytes.count }

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= bytes.count else { throw ParseError(description: "truncated file") }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }

        mutating func byte() throws -> UInt8 { try take(1)[0] }

        mutating func integer(_ count: Int) throws -> Int {
            try take(count).reduce(0) { $0 << 8 | Int($1) }
        }

        mutating func variableLength() throws -> Int {
            var value = 0
            for _ in 0..<4 {
                let next = try byte()
                value = value << 7 | Int(next & 0x7F)
                if next < 0x80 { return value }
            }
            throw ParseError(description: "invalid variable-length value")
        }
    }
}

extension SMF {
    /// Events present in only one of the two files. End-of-track markers are ignored.
    public func differences(from other: SMF) -> (removed: [SMFEvent], added: [SMFEvent]) {
        (Self.subtract(other.events, from: events), Self.subtract(events, from: other.events))
    }

    private static func subtract(_ rhs: [SMFEvent], from lhs: [SMFEvent]) -> [SMFEvent] {
        var remaining: [SMFEvent: Int] = [:]
        for event in rhs { remaining[event, default: 0] += 1 }
        return lhs.filter { event in
            if event.bytes.starts(with: [0xFF, 0x2F]) { return false }
            guard let count = remaining[event], count > 0 else { return true }
            remaining[event] = count - 1
            return false
        }
    }
}
