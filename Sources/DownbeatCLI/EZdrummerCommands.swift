import ArgumentParser
import Foundation
import EZdrummerKit
import MIDIKit

struct EZdrummer: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ezdrummer",
        abstract: "Read EZdrummer 3 projects.",
        subcommands: [Inspect.self]
    )

    struct Inspect: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Report the library, preset, mixer, Song Tracks and clips of a saved project.",
            discussion: "Reads the file only. EZdrummer does not need to run. Save the project first."
        )

        @Argument(help: "An .ezd3p project.")
        var input: String

        @Flag(help: "List the hits of each clip, bar by bar.")
        var notes = false

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let url = URL(fileURLWithPath: input).standardizedFileURL
            let report = try ProjectReport(contentsOf: url, notes: notes)
            if json {
                try printJSON(report)
                return
            }
            print("library  \(report.library ?? "?")")
            print("mixer preset  \(report.mixerPreset ?? "?")\(report.presetAltered == true ? "  (altered)" : "")")
            // The labeled channels are the faders of the mixer. --json lists every channel.
            for channel in report.mixer where channel.name != nil {
                let flags = (channel.mute == true ? "  muted" : "") + (channel.solo == true ? "  solo" : "")
                print("channel  \(channel.name ?? "")  volume \(channel.volume?.formatted() ?? "?")"
                    + "  pan \(channel.pan?.formatted() ?? "?")\(flags)")
            }
            for track in report.songTracks {
                print("track  \(track.name)  \(track.tempo?.formatted() ?? "?") bpm  \(track.signature)")
                for clip in track.clips {
                    print("  bar \(clip.startBar)  \(clip.name)  \(clip.bars.formatted()) \(clip.bars == 1 ? "bar" : "bars")  \(clip.noteCount) notes")
                    for line in MIDIReport.lines(clip.barList ?? []) { print("    \(line)") }
                }
            }
            for warning in report.warnings { print("warning  \(warning)") }
        }
    }
}
