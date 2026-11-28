import ArgumentParser
import Foundation
import DownbeatKit

struct Logic: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control Logic Pro.",
        subcommands: [
            Check.self, Inspect.self, StatusCommand.self, Project.self, Tempo.self,
            TrackCommands.self, Region.self, NoteCommands.self, LogicMIDICommands.self, MixerCommands.self,
            MarkerCommands.self, PluginCommands.self, AudioCommands.self,
            Play.self, Stop.self, Record.self,
        ]
    )
}

struct LogicMIDICommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "midi",
        abstract: "Bring MIDI files into Logic Pro.",
        subcommands: [Import.self]
    )

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Import a MIDI file onto new tracks, keeping the project tempo. Does not save the project."
        )

        @Argument(help: "A .mid file.")
        var input: String

        @Option(help: "Bar where the content starts.")
        var bar = 1

        @OptionGroup var target: ProjectOption

        func validate() throws {
            if bar < 1 { throw ValidationError("The bar must be 1 or more.") }
        }

        func run() throws {
            let source = URL(fileURLWithPath: input).standardizedFileURL
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw ValidationError("\(source.path) does not exist.")
            }
            for track in try target.app().importMIDI(from: source, atBar: bar) {
                print("\(track.number.map(String.init) ?? "?")  \(track.name)")
            }
        }
    }
}
