import ArgumentParser
import Foundation
import MIDIKit

private func url(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL }

private func data(at path: String) throws -> Data {
    guard let data = try? Data(contentsOf: url(path)) else {
        throw ValidationError("\(url(path).path) cannot be read.")
    }
    return data
}

private func arrangement(at path: String) throws -> Arrangement {
    try Arrangement(json: data(at: path), directory: url(path).deletingLastPathComponent())
}

/// Replaces the file in one step, keeping a symbolic link in place.
private func save(_ arrangement: Arrangement, to path: String) throws {
    try arrangement.json().write(to: url(path).resolvingSymlinksInPath(), options: .atomic)
}

private func count(_ number: Int, _ word: String) -> String { "\(number) \(word)\(number == 1 ? "" : "s")" }

extension BuildMode: ExpressibleByArgument {}

extension MIDICommands {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write the MIDI files of an arrangement into one folder.",
            discussion: """
                --per section writes <section>.mid. --per part writes <section>/<clip>.mid. \
                The folder gets \(Staging.manifestName), which lists every file created.
                """
        )

        @Argument(help: "Arrangement JSON file.")
        var input: String

        @Option(help: "Folder to write into. Must be new or empty, unless --replace is given.")
        var output: String

        @Option(help: "One file per section or per part.")
        var per = BuildMode.section

        @Option(help: "Build only this section. Repeat for more.")
        var section: [String] = []

        @Flag(help: "Replace the files of an earlier build in the folder.")
        var replace = false

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let resolved = try arrangement(at: input).resolve()
            let clips = try resolved.clips(per: per, sections: section)
            let directory = url(output)
            let manifest = try Staging.write(clips, source: url(input).path, to: directory, replace: replace)
            if json {
                try printJSON(manifest)
                return
            }
            for file in manifest.files {
                print("\(directory.appendingPathComponent(file.path).path)  \(count(file.bars, "bar"))")
            }
            print(directory.appendingPathComponent(Staging.manifestName).path)
            for part in resolved.sections where section.isEmpty || section.contains(part.name) {
                guard !part.emptyBars.isEmpty else { continue }
                let list = part.emptyBars.map(String.init).joined(separator: ", ")
                let effect = per == .section ? "silent" : "in no file"
                print("\(part.name): no part covers bars \(list). They are \(effect).")
            }
        }
    }

    struct Inspect: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Report tempo, meter, length and the notes of MIDI files, bar by bar.",
            discussion: """
                Positions count beats from 1, so 3.5 in 4/4 is 3&. In text output, f marks a flam \
                and the number in brackets is the velocity.
                """
        )

        @Argument(help: "MIDI files.")
        var inputs: [String]

        @Option(help: "Drum map: ezdrummer or a .json file.")
        var map: String?

        @Option(help: "Take the drum map from this arrangement.")
        var arrangement: String?

        @Flag(help: "Print JSON.")
        var json = false

        func validate() throws {
            if map != nil && arrangement != nil { throw ValidationError("Give --map or --arrangement, not both.") }
        }

        func run() throws {
            let drumMap = try arrangement.map { try DownbeatCLI.arrangement(at: $0).drumMap }
                ?? map.map(DrumMap.load) ?? .ezdrummer
            let reports = try inputs.map {
                try MIDIReport(data: data(at: $0), file: url($0).path, drumMap: drumMap)
            }
            if json {
                try printJSON(reports)
                return
            }
            for report in reports {
                print(report.file)
                let tempo = report.tempo.map { "\($0.bpm.formatted()) bpm" }.joined(separator: ", ")
                let meter = report.meter.map(\.signature).joined(separator: ", ")
                print("\(tempo)  \(meter)  \(count(report.bars, "bar"))  \(report.lengthBeats.formatted()) beats")
                for marker in report.markers { print("marker  bar \(marker.bar)  \(marker.name)") }
                for line in MIDIReport.lines(report.barList) { print(line) }
                if report.unpairedNotes > 0 { print("\(count(report.unpairedNotes, "note")) without a start or end") }
            }
        }
    }

    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Replace, copy or remove drum voices across parts of an arrangement.",
            discussion: """
                All operations are checked before the file is written once. Rewriting normalizes \
                the layout of the file. Build again to update the MIDI files.
                """
        )

        @Argument(help: "Arrangement JSON file.")
        var input: String

        @Argument(help: "Operations JSON file.")
        var operations: String

        @Flag(help: "Report what would change without writing.")
        var dryRun = false

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let original = try DownbeatCLI.arrangement(at: input)
            let batch = try EditBatch(json: data(at: operations))
            let (edited, report) = try original.applying(batch)
            if report.changed && !dryRun { try save(edited, to: input) }
            if json {
                try printJSON(report)
                return
            }
            for (index, operation) in report.operations.enumerated() {
                print("\(index + 1)  \(operation.op)")
                if operation.parts.isEmpty { print("  no notes matched") }
                for part in operation.parts {
                    var line = "  \(part.section) / \(part.clip)  \(part.action)  matched \(part.matched)"
                    line += "  removed \(part.removed)  added \(part.added)  changed \(part.changed)"
                    if part.voicesWrittenOut > 0 {
                        line += "  (\(count(part.voicesWrittenOut, "GUS voice")) written out as notes)"
                    }
                    print(line)
                }
            }
            if !report.changed {
                print("Nothing to change.")
            } else if dryRun {
                print("Dry run. Nothing was written.")
            } else {
                print("Saved \(url(input).path)")
            }
        }
    }

    struct Humanize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Store a seeded humanization rule in an arrangement. midi build applies it.",
            discussion: """
                The notes in the file stay straight, so running it again does not add up. \
                Accents keep their velocity. Both strokes of a flam move together. \
                A rule replaces the one with the same section, part, bars and articulations.
                """
        )

        @Argument(help: "Arrangement JSON file.")
        var input: String

        @Option(help: "Section name.")
        var section: String

        @Option(help: "Only this clip, such as \"16 fill b\".")
        var part: String?

        @Option(help: "Only these section bars, such as 9-12.")
        var bars: String?

        @Option(help: "Only this articulation or voice. Repeat for more.")
        var articulation: [String] = []

        @Option(help: "Seed. The same seed gives the same result.")
        var seed: Int?

        @Option(help: "Largest shift in quarter notes, up to 0.03125.")
        var timing: Double = 0

        @Option(help: "Largest velocity change.")
        var velocity = 0

        @Option(help: "Chance, 0 to 1, of leaving out a hit without an accent.")
        var drop: Double = 0

        @Flag(help: "Remove the rules of the section, or of the part.")
        var clear = false

        @Flag(help: "Report without writing.")
        var dryRun = false

        func validate() throws {
            if clear { return }
            guard seed != nil else { throw ValidationError("Give --seed.") }
            if timing == 0 && velocity == 0 && drop == 0 {
                throw ValidationError("Give --timing, --velocity or --drop.")
            }
        }

        func run() throws {
            var edited = try DownbeatCLI.arrangement(at: input)
            let before = try edited.resolve()
            if clear {
                let removed = edited.clearHumanize(section: section, part: part)
                guard removed > 0 else {
                    print("No rules to remove.")
                    return
                }
            } else {
                let rule = Arrangement.HumanizeRule(
                    section: section, part: part, bars: bars, articulations: articulation, seed: seed ?? 0,
                    timing: timing, velocity: velocity, drop: drop
                )
                guard edited.setHumanize(rule) else {
                    print("The rule is already set.")
                    return
                }
            }
            let after = try edited.resolve()
            for (old, new) in zip(before.sections, after.sections) {
                for (a, b) in zip(old.parts, new.parts) where a.hits != b.hits {
                    let dropped = a.hits.count - b.hits.count
                    let moved = zip(a.hits, b.hits).filter { $0 != $1 }.count
                    print("\(new.name) / \(b.clip)  \(dropped != 0 ? "\(count(abs(dropped), "hit")) \(dropped > 0 ? "fewer" : "more")" : "\(count(moved, "hit")) differ")")
                }
            }
            if dryRun {
                print("Dry run. Nothing was written.")
            } else {
                try save(edited, to: input)
                print("Saved \(url(input).path)")
            }
        }
    }
}
