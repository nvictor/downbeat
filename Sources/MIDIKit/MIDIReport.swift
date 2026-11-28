import Foundation

/// The content of a MIDI file, bar by bar.
public struct MIDIReport: Encodable, Sendable {
    public struct Tempo: Encodable, Equatable, Sendable {
        public let beat: Double
        public let bpm: Double
    }

    public struct Signature: Encodable, Equatable, Sendable {
        public let beat: Double
        public let signature: String
    }

    public struct Marker: Encodable, Equatable, Sendable {
        public let bar: Int
        public let beat: Double
        public let name: String
    }

    public struct Grace: Encodable, Equatable, Sendable {
        /// Quarter notes before the main stroke.
        public let offset: Double
        public let velocity: Int
        public let duration: Double
    }

    public struct Note: Encodable, Equatable, Sendable {
        /// The beat of the bar, from 1. In 4/4, 3.5 is `3&`.
        public let position: Double
        /// Quarter notes from the start of the file.
        public let beat: Double
        public let duration: Double
        public let pitch: Int
        public let articulation: String?
        public let velocity: Int
        public let releaseVelocity: Int
        public let channel: Int
        public var flam: Grace?
    }

    public struct Bar: Encodable, Sendable {
        public let bar: Int
        /// The first earlier bar with the same notes.
        public var sameAs: Int?
        public let notes: [Note]
    }

    public let file: String
    public let name: String?
    public let format: Int
    public let ticksPerQuarter: Int
    public let tempo: [Tempo]
    public let meter: [Signature]
    public let lengthBeats: Double
    public let bars: Int
    public let markers: [Marker]
    public let barList: [Bar]
    /// Channel and system events other than notes.
    public let otherEvents: Int
    public let unpairedNotes: Int

    public init(data: Data, file: String, drumMap: DrumMap) throws {
        let smf = try SMF(data: data)
        let ppq = smf.ticksPerQuarter
        guard ppq > 0, ppq < 0x8000 else {
            throw LayoutError(description: "\(file) counts time in frames, which is not supported")
        }
        func beats(_ tick: Int) -> Double { (Double(tick) / Double(ppq) * 1_000_000).rounded() / 1_000_000 }
        let ordered = smf.events.sorted { $0.tick < $1.tick }
        func metas(_ type: UInt8) -> [SMFEvent] { ordered.filter { $0.bytes.starts(with: [0xFF, type]) } }
        func text(_ event: SMFEvent) -> String { String(decoding: event.bytes.dropFirst(2), as: UTF8.self) }

        let signatures: [(tick: Int, meter: Meter)] = metas(0x58).compactMap { event in
            guard event.bytes.count >= 4, event.bytes[2] > 0, event.bytes[3] <= 5 else { return nil }
            return (event.tick, Meter(numerator: Int(event.bytes[2]), denominator: 1 << Int(event.bytes[3])))
        }
        let length = smf.bounds.end
        let paired = smf.pairedNotes()

        self.file = file
        name = metas(0x03).first.map(text)
        format = smf.format
        ticksPerQuarter = ppq
        tempo = metas(0x51).compactMap { event in
            let microseconds = event.bytes.dropFirst(2).reduce(0) { $0 << 8 | Int($1) }
            guard microseconds > 0 else { return nil }
            return Tempo(beat: beats(event.tick), bpm: (60_000_000_000 / Double(microseconds)).rounded() / 1000)
        }
        meter = signatures.map { Signature(beat: beats($0.tick), signature: $0.meter.description) }
        lengthBeats = beats(length)
        let list = Self.bars(of: paired.notes, ticksPerQuarter: ppq, signatures: signatures, length: length, drumMap: drumMap)
        barList = list.bars
        bars = list.bars.count
        markers = metas(0x06).map { event in
            Marker(bar: list.starts.lastIndex { $0 <= event.tick }.map { $0 + 1 } ?? 1,
                   beat: beats(event.tick), name: text(event))
        }
        otherEvents = smf.events.filter { (0xA0...0xF7).contains($0.bytes[0]) }.count
        unpairedNotes = paired.unpaired
    }

    /// Sorts notes into bars. A quieter stroke of the same pitch at most 1/8 quarter
    /// before another is read as the grace stroke of a flam.
    public static func bars(
        of notes: [SMFNote], ticksPerQuarter ppq: Int, signatures: [(tick: Int, meter: Meter)] = [],
        length: Int, drumMap: DrumMap
    ) -> (bars: [Bar], starts: [Int]) {
        func beats(_ tick: Int) -> Double { (Double(tick) / Double(ppq) * 1_000_000).rounded() / 1_000_000 }
        var layout: [(start: Int, meter: Meter)] = []
        var start = 0
        while start < length && layout.count < 100_000 {
            let meter = signatures.last { $0.tick <= start }?.meter ?? .common
            layout.append((start, meter))
            start += max(meter.numerator * ppq * 4 / meter.denominator, 1)
        }

        var graces: [Int: SMFNote] = [:]
        var folded: Set<Int> = []
        for (index, note) in notes.enumerated() {
            let main = notes.indices.dropFirst(index + 1).first {
                notes[$0].pitch == note.pitch && notes[$0].channel == note.channel && notes[$0].tick > note.tick
            }
            if let main, notes[main].tick - note.tick <= ppq / 8, note.velocity < notes[main].velocity,
               graces[main] == nil, !folded.contains(index) {
                graces[main] = note
                folded.insert(index)
            }
        }

        let tolerance = ppq / 32
        var inBar: [Int: [(note: Note, key: [Int])]] = [:]
        for (index, note) in notes.enumerated() where !folded.contains(index) {
            guard let bar = layout.lastIndex(where: { $0.start <= note.tick + tolerance }) else { continue }
            let beat = ppq * 4 / layout[bar].meter.denominator
            let relative = note.tick - layout[bar].start
            let grace = graces[index]
            let entry = Note(
                position: (Double(relative) / Double(beat) * 1000).rounded() / 1000 + 1,
                beat: beats(note.tick), duration: beats(note.length), pitch: note.pitch,
                articulation: drumMap.name(of: note.pitch), velocity: note.velocity,
                releaseVelocity: note.releaseVelocity, channel: note.channel,
                flam: grace.map { Grace(offset: beats(note.tick - $0.tick), velocity: $0.velocity, duration: beats($0.length)) }
            )
            let key = [note.pitch, relative, note.length, note.velocity,
                       grace.map { note.tick - $0.tick } ?? 0, grace?.velocity ?? 0]
            inBar[bar, default: []].append((entry, key))
        }

        var seen: [[[Int]]: Int] = [:]
        let bars = layout.indices.map { index in
            let entries = inBar[index] ?? []
            let signature = entries.map(\.key).sorted { $0.lexicographicallyPrecedes($1) }
            var bar = Bar(bar: index + 1, notes: entries.map(\.note))
            if !signature.isEmpty {
                if let first = seen[signature] { bar.sameAs = first } else { seen[signature] = index + 1 }
            }
            return bar
        }
        return (bars, layout.map(\.start))
    }

    /// One line per bar and articulation, with the positions it plays.
    public static func lines(_ bars: [Bar]) -> [String] {
        bars.flatMap { bar -> [String] in
            let title = "bar \(bar.bar)" + (bar.sameAs.map { "  (same as bar \($0))" } ?? "")
            guard !bar.notes.isEmpty else { return ["\(title)  empty"] }
            let groups = Dictionary(grouping: bar.notes) { $0.articulation ?? "pitch \($0.pitch)" }
            return [title] + groups.keys.sorted().map { name in
                let hits = groups[name]!.map {
                    "\($0.position.formatted(.number.precision(.fractionLength(0...3))))\($0.flam == nil ? "" : "f")(\($0.velocity))"
                }
                return "  \(name)  \(hits.joined(separator: " "))"
            }
        }
    }
}
