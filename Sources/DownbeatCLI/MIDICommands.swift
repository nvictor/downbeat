import ArgumentParser
import Foundation
import DownbeatKit

struct MIDICommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "midi",
        abstract: "Work with MIDI files.",
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
