import ArgumentParser
import Foundation
import DownbeatKit

struct AudioCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audio",
        abstract: "Move audio files in and out of tracks.",
        subcommands: [Import.self, Export.self]
    )

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Place an audio file on an audio track. Does not save the project."
        )

        @Argument(help: "Audio file.")
        var input: String

        @Option(help: "Name or number of an audio track.")
        var track: String

        @Option(help: "Bar where the audio starts. Its bars must be free.")
        var bar: Int

        @OptionGroup var target: ProjectOption

        func validate() throws {
            if bar < 1 { throw ValidationError("--bar must be 1 or more.") }
        }

        func run() throws {
            let source = URL(fileURLWithPath: input).standardizedFileURL
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw ValidationError("\(source.path) does not exist.")
            }
            let used = try target.app().importAudio(from: source, track: track, bar: bar)
            print("Imported \(source.lastPathComponent) at bar \(bar) on \(used.name).")
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bounce one track to a WAVE file.",
            discussion: "Selects the track. Bit depth and other settings are the ones Logic Pro last used."
        )

        @Option(help: "Name or number of the track.")
        var track: String

        @Option(name: .shortAndLong, help: "New .wav file.")
        var output: String

        func run() throws {
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try LogicApp().exportAudio(track: track, to: url)
            print(url.path)
        }
    }
}
