import ArgumentParser
import Foundation
import LogicKit
import MIDIKit

struct Spike: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Throwaway round-trip experiments. Use a scratch project.",
        subcommands: [Export.self, Import.self, Replace.self, Tracks.self, Transpose.self, Diff.self]
    )

    struct Target: ParsableArguments {
        @Option(help: "Name of the scratch project that must be in front.")
        var project = "RoundTrip"

        func app() throws -> LogicApp {
            let app = try LogicApp()
            try app.requireProject(named: project)
            return app
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Export the selected region.")
        @OptionGroup var target: Target
        @Argument(help: "New .mid file.") var output: String

        func run() throws {
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try target.app().exportSelection(to: url)
            let file = try MIDIFile(contentsOf: url)
            let removed = try file.thinPitchBend()
            if removed > 0 {
                try file.save(to: url)
                FileHandle.standardError.write(Data("Removed \(removed) extra pitch bend events.\n".utf8))
            }
            print(url.path)
        }
    }

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Import a MIDI file onto a new track.")
        @OptionGroup var target: Target
        @Argument(help: "Existing .mid file.") var input: String

        func run() throws {
            let app = try target.app()
            try app.importMIDI(from: URL(fileURLWithPath: input).standardizedFileURL)
            try printJSON(app.tracks())
        }
    }

    struct Replace: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Replace the selected region with a MIDI file, on the same track and bars."
        )
        @OptionGroup var target: Target
        @Argument(help: "Edited .mid file, exported from the selected region.") var input: String

        func run() throws {
            let app = try target.app()
            let placement = try app.selectedPlacement()
            let source = URL(fileURLWithPath: input).standardizedFileURL
            let prepared = FileManager.default.temporaryDirectory
                .appendingPathComponent("logic-cli-\(UUID().uuidString).mid")
            defer { try? FileManager.default.removeItem(at: prepared) }

            let file = try MIDIFile(contentsOf: source)
            let smf = try SMF(data: Data(contentsOf: source))
            // A file from an earlier replace already ends with an event on the last tick.
            let reachesEnd = smf.events.contains { $0.tick == smf.endTick - 1 }
            if !reachesEnd { try file.extend(toTick: smf.endTick) }
            try file.save(to: prepared)

            try app.replaceSelectedRegion(with: prepared, at: placement)
            try printJSON(app.tracks())
        }
    }

    struct Tracks: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List visible tracks and regions.")

        func run() throws {
            try printJSON(LogicApp().tracks())
        }
    }

    struct Transpose: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Transpose every note in a MIDI file.")
        @Argument var input: String
        @Argument var output: String
        @Option var semitones: Int

        func run() throws {
            let file = try MIDIFile(contentsOf: URL(fileURLWithPath: input))
            try file.transpose(semitones: semitones)
            try file.save(to: URL(fileURLWithPath: output))
        }
    }

    struct Diff: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Compare the events of two MIDI files.")
        @Argument var first: String
        @Argument var second: String

        func run() throws {
            let a = try SMF(data: Data(contentsOf: URL(fileURLWithPath: first)))
            let b = try SMF(data: Data(contentsOf: URL(fileURLWithPath: second)))
            let changes = a.differences(from: b)
            if a.ticksPerQuarter != b.ticksPerQuarter {
                print("resolution: \(a.ticksPerQuarter) != \(b.ticksPerQuarter)")
            }
            for event in changes.removed { print("- \(describe(event))") }
            for event in changes.added { print("+ \(describe(event))") }
            if a.ticksPerQuarter != b.ticksPerQuarter || !changes.removed.isEmpty || !changes.added.isEmpty {
                throw ExitCode.failure
            }
            print("identical events")
        }

        private func describe(_ event: SMFEvent) -> String {
            let bytes = event.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "track \(event.track) tick \(event.tick): \(bytes)"
        }
    }
}
