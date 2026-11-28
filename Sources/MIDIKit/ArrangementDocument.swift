import Foundation

/// A song written as sections, named parts and drum voices. See `docs/arrangements.md`.
/// All beats and durations are quarter notes.
public struct Arrangement: Equatable, Sendable {
    public struct Flam: Equatable, Sendable {
        /// How long before the main stroke the grace stroke starts.
        public var offset = 0.0625
        public var velocity = 44
        public var duration = 0.025
    }

    /// A line of hits written in GUS.
    public struct Voice: Equatable, Sendable {
        /// Cycled over the hits of each bar.
        public var articulations: [String]
        /// One per bar, cycled over the bars of the part.
        public var gus: [String]
        /// Cycled over the hits of each bar.
        public var velocities: [Int] = [100]
        public var duration: Double?
        public var accent = false
        public var flam: Flam?
    }

    public struct Note: Equatable, Sendable {
        /// Exactly one of `articulation` and `pitch` is set.
        public var articulation: String?
        public var pitch: Int?
        /// Start from the beginning of the part.
        public var beat: Double
        public var duration: Double?
        public var velocity = 100
        public var releaseVelocity = 64
        public var accent = false
        public var flam: Flam?
    }

    public struct Part: Equatable, Sendable {
        /// First bar in the section, counted from 1.
        public var bar: Int
        public var bars: Int
        public var name: String
        /// Another part whose voices and notes this one plays: `clip` or `section/clip`.
        public var use: String?
        public var voices: [Voice] = []
        public var notes: [Note] = []

        /// The name of the clip, such as `08 fill a`.
        public var clip: String { String(format: "%02d %@", bar, name) }
    }

    public struct Section: Equatable, Sendable {
        /// The PAL letter, such as `A`.
        public var id: String?
        public var name: String
        public var bars: Int?
        public var tempo: Double?
        public var meter: String?
        public var parts: [Part]
    }

    /// Humanization applied when MIDI is built. The arrangement keeps the straight notes.
    public struct HumanizeRule: Equatable, Sendable {
        public var section: String
        public var part: String?
        /// Section bars, such as `8` or `9-12`.
        public var bars: String?
        /// Articulations or voices. Empty means all.
        public var articulations: [String] = []
        public var seed: Int
        /// Largest shift in quarter notes.
        public var timing: Double = 0
        /// Largest velocity change.
        public var velocity = 0
        /// Chance of leaving out a hit that has no accent.
        public var drop: Double = 0

        public init(
            section: String, part: String? = nil, bars: String? = nil, articulations: [String] = [],
            seed: Int, timing: Double = 0, velocity: Int = 0, drop: Double = 0
        ) {
            self.section = section
            self.part = part
            self.bars = bars
            self.articulations = articulations
            self.seed = seed
            self.timing = timing
            self.velocity = velocity
            self.drop = drop
        }

        func hasSameScope(as other: HumanizeRule) -> Bool {
            section == other.section && part == other.part && bars == other.bars
                && Set(articulations) == Set(other.articulations)
        }
    }

    public var title: String?
    public var pal: String?
    public var tempo: Double?
    public var meter: String?
    public var channel: Int?
    public var sections: [Section]
    public var humanize: [HumanizeRule] = []
    public let drumMap: DrumMap
    /// The `drumMap` value as written, kept for rewriting the file.
    private let drumMapSource: Data

    // MARK: Reading

    /// `directory` is where a relative drum map path starts.
    public init(json: Data, directory: URL? = nil) throws {
        var reader = try JSONReader(JSONReader.parse(json), "the arrangement")
        let version = try reader.required(reader.int("version"), "version")
        guard version == 1 else { throw reader.fail("version \(version) is not supported. Use 1.") }
        title = try reader.string("title")
        pal = try reader.string("pal")
        tempo = try reader.double("tempo")
        meter = try reader.string("meter")
        channel = try reader.int("channel")
        let map = reader.raw("drumMap") ?? "ezdrummer"
        drumMap = try DrumMap.read(map, relativeTo: directory)
        drumMapSource = try JSONSerialization.data(withJSONObject: map, options: [.fragmentsAllowed, .sortedKeys])
        let sectionValues = try reader.required(reader.array("sections"), "sections")
        sections = try sectionValues.enumerated().map { try Section($1, "section \($0 + 1)") }
        humanize = try (reader.array("humanize") ?? []).enumerated().map {
            try HumanizeRule($1, "humanize rule \($0 + 1)")
        }
        try reader.finish()
    }

    // MARK: Writing

    /// The file text, with stable key order.
    public func json() throws -> Data {
        let map = try Self.value(JSONReader.parse(drumMapSource))
        let root = JSONValue.fields([
            ("version", .int(1)),
            ("title", title.map(JSONValue.string)),
            ("pal", pal.map(JSONValue.string)),
            ("tempo", tempo.map(JSONValue.double)),
            ("meter", meter.map(JSONValue.string)),
            ("channel", channel.map(JSONValue.int)),
            ("drumMap", map),
            ("sections", .array(sections.map(\.value))),
            ("humanize", humanize.isEmpty ? nil : .array(humanize.map(\.value))),
        ])
        return Data((root.text() + "\n").utf8)
    }

    private static func value(_ object: Any) throws -> JSONValue {
        if let text = object as? String { return .string(text) }
        if let list = object as? [Any] { return .array(try list.map(value)) }
        if let fields = object as? [String: Any] {
            return .object(try fields.keys.sorted().map { ($0, try value(fields[$0]!)) })
        }
        if let number = JSONReader.integer(object) { return .int(number) }
        throw LayoutError(description: "the drum map holds a value that cannot be written back")
    }
}

private func oneOrList<T>(_ items: [T], _ value: (T) -> JSONValue) -> JSONValue {
    items.count == 1 ? value(items[0]) : .array(items.map(value))
}

extension Arrangement.Section {
    init(_ value: Any, _ place: String) throws {
        var reader = try JSONReader(value, place)
        let name = try reader.required(reader.string("name"), "name")
        reader = try JSONReader(value, "section \(name)")
        _ = reader.raw("name")
        self.name = name
        id = try reader.string("id")
        bars = try reader.int("bars")
        tempo = try reader.double("tempo")
        meter = try reader.string("meter")
        parts = try reader.required(reader.array("parts"), "parts").enumerated().map {
            try Arrangement.Part($1, "section \(name), part \($0 + 1)")
        }
        try reader.finish()
    }

    var value: JSONValue {
        .fields([
            ("id", id.map(JSONValue.string)),
            ("name", .string(name)),
            ("bars", bars.map(JSONValue.int)),
            ("tempo", tempo.map(JSONValue.double)),
            ("meter", meter.map(JSONValue.string)),
            ("parts", .array(parts.map(\.value))),
        ])
    }
}

extension Arrangement.Part {
    init(_ value: Any, _ place: String) throws {
        var reader = try JSONReader(value, place)
        bar = try reader.required(reader.int("bar"), "bar")
        bars = try reader.required(reader.int("bars"), "bars")
        name = try reader.required(reader.string("name"), "name")
        use = try reader.string("use")
        voices = try (reader.array("voices") ?? []).enumerated().map {
            try Arrangement.Voice($1, "\(place), voice \($0 + 1)")
        }
        notes = try (reader.array("notes") ?? []).enumerated().map {
            try Arrangement.Note($1, "\(place), note \($0 + 1)")
        }
        try reader.finish()
    }

    var value: JSONValue {
        .fields([
            ("bar", .int(bar)),
            ("bars", .int(bars)),
            ("name", .string(name)),
            ("use", use.map(JSONValue.string)),
            ("voices", voices.isEmpty ? nil : .array(voices.map(\.value))),
            ("notes", notes.isEmpty ? nil : .array(notes.map(\.value))),
        ])
    }
}

extension Arrangement.Voice {
    init(_ value: Any, _ place: String) throws {
        var reader = try JSONReader(value, place)
        articulations = try reader.required(
            reader.oneOrMany("articulation", "a name") { $0 as? String }, "articulation")
        gus = try reader.required(reader.oneOrMany("gus", "a GUS line") { $0 as? String }, "gus")
        velocities = try reader.oneOrMany("velocity", "a whole number", JSONReader.integer) ?? [100]
        duration = try reader.double("duration")
        accent = try reader.bool("accent") ?? false
        flam = try reader.raw("flam").map { try Arrangement.Flam($0, "\(place), flam") }
        try reader.finish()
    }

    var value: JSONValue {
        .fields([
            ("articulation", oneOrList(articulations, JSONValue.string)),
            ("velocity", velocities == [100] ? nil : oneOrList(velocities, JSONValue.int)),
            ("duration", duration.map(JSONValue.double)),
            ("accent", accent ? .bool(true) : nil),
            ("flam", flam.map(\.value)),
            ("gus", oneOrList(gus, JSONValue.string)),
        ])
    }
}

extension Arrangement.Note {
    init(_ value: Any, _ place: String) throws {
        var reader = try JSONReader(value, place)
        articulation = try reader.string("articulation")
        pitch = try reader.int("pitch")
        beat = try reader.required(reader.double("beat"), "beat")
        duration = try reader.double("duration")
        velocity = try reader.int("velocity") ?? 100
        releaseVelocity = try reader.int("releaseVelocity") ?? 64
        accent = try reader.bool("accent") ?? false
        flam = try reader.raw("flam").map { try Arrangement.Flam($0, "\(place), flam") }
        try reader.finish()
    }

    var value: JSONValue {
        .fields([
            ("articulation", articulation.map(JSONValue.string)),
            ("pitch", pitch.map(JSONValue.int)),
            ("beat", .double(beat)),
            ("duration", duration.map(JSONValue.double)),
            ("velocity", .int(velocity)),
            ("releaseVelocity", releaseVelocity == 64 ? nil : .int(releaseVelocity)),
            ("accent", accent ? .bool(true) : nil),
            ("flam", flam.map(\.value)),
        ])
    }
}

extension Arrangement.Flam {
    init(_ value: Any, _ place: String) throws {
        var reader = try JSONReader(value, place)
        offset = try reader.double("offset") ?? offset
        velocity = try reader.int("velocity") ?? velocity
        duration = try reader.double("duration") ?? duration
        try reader.finish()
    }

    var value: JSONValue {
        .fields([("offset", .double(offset)), ("velocity", .int(velocity)), ("duration", .double(duration))])
    }
}

extension Arrangement.HumanizeRule {
    init(_ value: Any, _ place: String) throws {
        var reader = try JSONReader(value, place)
        section = try reader.required(reader.string("section"), "section")
        part = try reader.string("part")
        bars = try reader.string("bars")
        articulations = try reader.oneOrMany("articulations", "a name") { $0 as? String } ?? []
        seed = try reader.required(reader.int("seed"), "seed")
        timing = try reader.double("timing") ?? 0
        velocity = try reader.int("velocity") ?? 0
        drop = try reader.double("drop") ?? 0
        try reader.finish()
    }

    var value: JSONValue {
        .fields([
            ("section", .string(section)),
            ("part", part.map(JSONValue.string)),
            ("bars", bars.map(JSONValue.string)),
            ("articulations", articulations.isEmpty ? nil : .array(articulations.map(JSONValue.string))),
            ("seed", .int(seed)),
            ("timing", timing == 0 ? nil : .double(timing)),
            ("velocity", velocity == 0 ? nil : .int(velocity)),
            ("drop", drop == 0 ? nil : .double(drop)),
        ])
    }
}
