import Foundation

/// Names for the pitches of a drum kit, and groups of those names.
public struct DrumMap: Equatable, Sendable {
    /// Articulation name to pitch.
    public let articulations: [String: Int]
    /// Group name, such as `hi-hat`, to articulation names.
    public let voices: [String: [String]]

    public init(articulations: [String: Int], voices: [String: [String]] = [:]) throws {
        var names: [Int: String] = [:]
        for (name, pitch) in articulations.sorted(by: { $0.key < $1.key }) {
            guard (0...127).contains(pitch) else {
                throw LayoutError(description: "drum map: \(name) must have a pitch of 0 to 127")
            }
            if let other = names.updateValue(name, forKey: pitch) {
                throw LayoutError(description: "drum map: \(other) and \(name) share pitch \(pitch)")
            }
        }
        for (voice, members) in voices {
            if let unknown = members.first(where: { articulations[$0] == nil }) {
                throw LayoutError(description: "drum map: voice \(voice) names unknown articulation \"\(unknown)\"")
            }
        }
        self.articulations = articulations
        self.voices = voices
    }

    /// EZdrummer 3 pitches, checked against one project that uses the EZX 70s library.
    /// Kick, snare and the tight hi-hat edge are inferred. Other libraries may differ.
    public static let ezdrummer = try! DrumMap(
        articulations: [
            "kick": 36, "snare-center": 38, "floor-tom-1-center": 43, "crash-1": 49, "ride-bow": 51,
            "hi-hat-tight-edge": 62, "hi-hat-tight-tip": 63,
        ],
        voices: [
            "snare": ["snare-center"], "toms": ["floor-tom-1-center"], "cymbals": ["crash-1"],
            "hi-hat": ["hi-hat-tight-tip", "hi-hat-tight-edge"], "ride": ["ride-bow"],
        ]
    )

    public func name(of pitch: Int) -> String? {
        articulations.first { $0.value == pitch }?.key
    }

    /// The articulations named by `names`, each an articulation or a voice.
    public func expand(_ names: [String]) throws -> Set<String> {
        var result: Set<String> = []
        for name in names {
            if articulations[name] != nil {
                result.insert(name)
            } else if let members = voices[name] {
                result.formUnion(members)
            } else {
                throw LayoutError(description: "unknown articulation or voice \"\(name)\". Known: \(knownNames)")
            }
        }
        return result
    }

    var knownNames: String { Set(articulations.keys).union(voices.keys).sorted().joined(separator: ", ") }

    /// A built-in name, a path to a map file relative to `directory`, or a map object.
    static func read(_ value: Any, relativeTo directory: URL?, depth: Int = 0) throws -> DrumMap {
        if let text = value as? String {
            if text == "ezdrummer" { return .ezdrummer }
            guard text.hasSuffix(".json"), depth < 4 else {
                throw LayoutError(description: "drum map \"\(text)\" is neither \"ezdrummer\" nor a .json file")
            }
            let url = URL(fileURLWithPath: text, relativeTo: directory).standardizedFileURL
            guard let data = try? Data(contentsOf: url) else {
                throw LayoutError(description: "drum map \(url.path) cannot be read")
            }
            return try read(JSONReader.parse(data), relativeTo: url.deletingLastPathComponent(), depth: depth + 1)
        }
        var reader = try JSONReader(value, "drum map")
        let base = try reader.raw("extends").map { try read($0, relativeTo: directory, depth: depth + 1) }
        var articulations = base?.articulations ?? [:]
        var voices = base?.voices ?? [:]
        if let value = reader.raw("articulations") {
            guard let added = value as? [String: Any] else { throw reader.fail("\"articulations\" must be an object") }
            for (name, pitch) in added {
                guard let pitch = JSONReader.integer(pitch) else { throw reader.fail("\(name) needs a whole number") }
                articulations[name] = pitch
            }
        }
        if let value = reader.raw("voices") {
            guard let added = value as? [String: [String]] else {
                throw reader.fail("\"voices\" must map names to lists of articulations")
            }
            voices.merge(added) { _, new in new }
        }
        try reader.finish()
        return try DrumMap(articulations: articulations, voices: voices)
    }

    /// Reads `ezdrummer` or the path of a map file.
    public static func load(_ nameOrPath: String) throws -> DrumMap {
        try read(nameOrPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    }
}
