import CryptoKit
import Foundation

/// A MIDI file made from an arrangement.
public struct BuiltClip: Codable, Equatable, Sendable {
    /// Path relative to the output folder.
    public let path: String
    public let section: String
    /// Nil for a file holding a whole section.
    public let clip: String?
    /// First bar in the section.
    public let bar: Int
    public let bars: Int
    public var sha256 = ""
}

public enum BuildMode: String, Sendable, CaseIterable {
    case section, part
}

extension ResolvedArrangement {
    /// The files of one build, in playing order. Nothing is written.
    public func clips(per mode: BuildMode, sections only: [String] = []) throws -> [(info: BuiltClip, data: Data)] {
        if let unknown = only.first(where: { name in !sections.contains { $0.name == name } }) {
            throw LayoutError(description: "no section \"\(unknown)\"")
        }
        return sections.filter { only.isEmpty || only.contains($0.name) }.flatMap { section in
            func make(_ info: BuiltClip, _ data: Data) -> (info: BuiltClip, data: Data) {
                var info = info
                info.sha256 = sha256(data)
                return (info, data)
            }
            switch mode {
            case .section:
                let data = SMF.clip(
                    name: section.name, tempo: section.tempo, meter: section.meter,
                    length: section.bars * section.meter.barTicks,
                    notes: section.parts.flatMap { part in
                        part.hits.flatMap {
                            $0.notes(offsetBy: (part.bar - 1) * section.meter.barTicks, channel: channel)
                        }
                    },
                    markers: section.parts.map { (($0.bar - 1) * section.meter.barTicks, $0.clip) }
                )
                return [make(BuiltClip(
                    path: "\(section.name).mid", section: section.name, clip: nil, bar: 1, bars: section.bars
                ), data)]
            case .part:
                return section.parts.map { part in
                    let data = SMF.clip(
                        name: part.clip, tempo: section.tempo, meter: section.meter, length: part.length,
                        notes: part.hits.flatMap { $0.notes(offsetBy: 0, channel: channel) }
                    )
                    return make(BuiltClip(
                        path: "\(section.name)/\(part.clip).mid", section: section.name, clip: part.clip,
                        bar: part.bar, bars: part.bars
                    ), data)
                }
            }
        }
    }
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// The folder a build writes into, with a manifest of what it created.
public enum Staging {
    public static let manifestName = "downbeat-manifest.json"

    public struct Manifest: Codable, Equatable, Sendable {
        public var source: String
        public var files: [BuiltClip]
    }

    /// Writes the clips and the manifest into `directory`, which must be new or empty.
    /// With `replace`, it may hold an earlier build: files listed there and still unchanged
    /// are removed. Every check runs before the first change.
    public static func write(
        _ clips: [(info: BuiltClip, data: Data)], source: String, to directory: URL, replace: Bool = false
    ) throws -> Manifest {
        func fail(_ message: String) -> LayoutError { LayoutError(description: "\(message). Nothing was changed.") }
        let files = FileManager.default
        let manifestURL = directory.appendingPathComponent(manifestName)
        var isDirectory: ObjCBool = false
        let exists = files.fileExists(atPath: directory.path, isDirectory: &isDirectory)
        if exists && !isDirectory.boolValue { throw fail("\(directory.path) is not a folder") }
        let contents = exists ? try files.contentsOfDirectory(atPath: directory.path) : []

        var old: [BuiltClip] = []
        if contents.contains(where: { $0 != ".DS_Store" }) {
            guard replace else { throw fail("\(directory.path) is not empty. Pass --replace to update an earlier build") }
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
                throw fail("\(directory.path) has no readable \(manifestName)")
            }
            old = manifest.files
        }
        for file in old {
            let pieces = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !file.path.hasPrefix("/"), !pieces.contains(".."), file.path.hasSuffix(".mid") else {
                throw fail("the manifest lists the unsafe path \(file.path)")
            }
            if let data = try? Data(contentsOf: directory.appendingPathComponent(file.path)),
               sha256(data) != file.sha256 {
                throw fail("\(file.path) changed since it was built. Move it away first")
            }
        }
        for clip in clips {
            let path = clip.info.path
            if !old.contains(where: { $0.path.lowercased() == path.lowercased() }),
               files.fileExists(atPath: directory.appendingPathComponent(path).path) {
                throw fail("\(path) exists and is not part of the earlier build")
            }
        }

        for file in old {
            let url = directory.appendingPathComponent(file.path)
            guard files.fileExists(atPath: url.path) else { continue }
            try files.removeItem(at: url)
            let parent = url.deletingLastPathComponent()
            if parent.standardizedFileURL.path != directory.standardizedFileURL.path,
               (try? files.contentsOfDirectory(atPath: parent.path))?.isEmpty == true {
                try files.removeItem(at: parent)
            }
        }
        for clip in clips {
            let url = directory.appendingPathComponent(clip.info.path)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try clip.data.write(to: url, options: .withoutOverwriting)
        }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = Manifest(source: source, files: clips.map(\.info))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifest
    }
}
