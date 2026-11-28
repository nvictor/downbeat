import Foundation
import MIDIKit

/// What a saved EZdrummer 3 project holds. Reading never changes the file.
/// The format is undocumented. It was read from projects saved by version 3.1.2.
public struct ProjectReport: Encodable, Sendable {
    public struct Channel: Encodable, Sendable {
        /// The name in the file, such as `Snare` or `buss 2`.
        public let channel: String
        /// The label of a bus.
        public let name: String?
        /// As stored. Not decibels.
        public let volume: Double?
        public let pan: Double?
        public let mute: Bool?
        public let solo: Bool?
    }

    public struct Clip: Encodable, Sendable {
        public let name: String
        public let startBar: Int
        public let bars: Double
        /// Quarter notes from the start of the Song Track.
        public let startBeat: Double
        public let endBeat: Double
        /// Where the clip starts in its MIDI source, and how far it was moved.
        public let sourceStart: Double
        public let offset: Double
        public let sourceFile: String?
        public let noteCount: Int
        public let barList: [MIDIReport.Bar]?
    }

    public struct SongTrack: Encodable, Sendable {
        public let name: String
        public let tempo: Double?
        public let signature: String
        public let clips: [Clip]
    }

    public let pluginVersion: String?
    public let library: String?
    public let mixerPreset: String?
    public let kitPreset: String?
    public let presetAltered: Bool?
    public let mixer: [Channel]
    public let songTracks: [SongTrack]
    public let warnings: [String]

    /// With `notes`, each clip lists its hits bar by bar.
    public init(contentsOf url: URL, notes: Bool = false, drumMap: DrumMap = .ezdrummer) throws {
        guard let data = try? Data(contentsOf: url) else { throw ProjectError("\(url.path) cannot be read") }
        try self.init(text: String(decoding: data, as: UTF8.self), notes: notes, drumMap: drumMap)
    }

    public init(text: String, notes: Bool = false, drumMap: DrumMap = .ezdrummer) throws {
        let root = try Node.parse(text)
        guard let sampler = root.child("SAMPLER") else { throw ProjectError("this is not an EZdrummer 3 project") }
        var warnings: [String] = []
        pluginVersion = root.string("PlugVersion")
        if pluginVersion?.hasPrefix("3.1.") != true {
            warnings.append("Written by version \(pluginVersion ?? "unknown"). Only 3.1 was checked.")
        }
        library = sampler.child("HQ")?.string("soundlib")
        let editor = root.child("editorVars")
        mixerPreset = editor?.string("DrumsMixerPresetName")
        kitPreset = editor?.string("ChosenKitPresetName").flatMap { $0.isEmpty ? nil : $0 }
        presetAltered = editor?.flag("PresetAltered")
        mixer = (sampler.child("mixer")?.children ?? []).map { node in
            Channel(
                channel: node.name, name: node.string("username"), volume: node.number("volume"),
                pan: node.number("pan"), mute: node.flag("mute"), solo: node.flag("solo")
            )
        }
        songTracks = try root.all("SongTrack").map { track in
            let name = track.string("TrackName") ?? ""
            let signature = track.values("TimeSig")?.prefix(2).joined(separator: "/") ?? "4/4"
            let meter = Meter(signature) ?? .common
            let clips = try track.all("MidiLoop").map {
                try Self.clip($0, meter: meter, track: name, notes: notes, drumMap: drumMap)
            }
            return SongTrack(
                name: name, tempo: track.number("Tempo"), signature: signature,
                clips: clips.sorted { $0.startBeat < $1.startBeat }
            )
        }
        self.warnings = warnings
    }

    private static func clip(
        _ loop: Node, meter: Meter, track: String, notes: Bool, drumMap: DrumMap
    ) throws -> Clip {
        let sourceStart = loop.number("StartTime") ?? 0
        let offset = loop.number("Offset") ?? 0
        // `SongPart start end beats "name" …` places the clip on the Song Track.
        let part = loop.values("SongPart")
        let named = part.flatMap { $0.count > 3 ? $0 : nil }
        let start = named.flatMap { Double($0[0]) } ?? sourceStart + offset
        let end = named.flatMap { Double($0[1]) } ?? (loop.number("EndTime") ?? sourceStart) + offset
        let name = named?[3] ?? loop.string("Name") ?? ""

        // Positions beyond any real song would overflow the tick counts.
        func sane(_ value: Double) -> Bool { value.isFinite && abs(value) < 1_000_000 }
        guard sane(start), sane(end), sane(offset), end >= start else {
            throw ProjectError("\(track) / \(name): unreadable clip position")
        }

        // `Events packed start end …`, where packed is velocity, pitch and status bytes.
        let values = loop.child("MidiEvents")?.values("Events") ?? []
        guard values.count % 3 == 0 else { throw ProjectError("\(track) / \(name): unreadable note list") }
        let ppq = SMF.clipResolution
        let tolerance = 1.0 / 32
        let hits: [SMFNote] = try stride(from: 0, to: values.count, by: 3).compactMap { index in
            guard let packed = Int(values[index]), let from = Double(values[index + 1]),
                  let to = Double(values[index + 2]), sane(from), sane(to) else {
                throw ProjectError("\(track) / \(name): unreadable note list")
            }
            let at = from + offset
            let velocity = packed >> 16 & 0xFF
            guard packed & 0xF0 == 0x90, velocity > 0, at >= start - tolerance, at < end - tolerance else { return nil }
            return SMFNote(
                tick: Int(((at - start) * Double(ppq)).rounded()), length: Int(((to - from) * Double(ppq)).rounded()),
                pitch: packed >> 8 & 0xFF, velocity: velocity, channel: (packed & 0x0F) + 1
            )
        }.sorted { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }

        let bars = notes ? MIDIReport.bars(
            of: hits, ticksPerQuarter: ppq, signatures: [(0, meter)],
            length: Int(((end - start) * Double(ppq)).rounded()), drumMap: drumMap
        ).bars : nil
        return Clip(
            name: name, startBar: Int((start + tolerance) / meter.barQuarters) + 1,
            bars: (end - start) / meter.barQuarters, startBeat: start, endBeat: end,
            sourceStart: sourceStart, offset: offset, sourceFile: loop.string("FileName"),
            noteCount: hits.count, barList: bars
        )
    }
}
