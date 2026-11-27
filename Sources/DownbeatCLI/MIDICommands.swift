import ArgumentParser
import Foundation
import DownbeatKit
import MIDIKit

struct MIDICommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "midi",
        abstract: "Work with MIDI files and ports.",
        subcommands: [Import.self, Ports.self]
    )

    struct Ports: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List the MIDI ports of this Mac. Logic Pro is not needed."
        )

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let ports = MIDIPort.all()
            if json {
                try printJSON(ports)
                return
            }
            if ports.isEmpty {
                print("No MIDI ports.")
            }
            for port in ports {
                print("\(port.direction.rawValue)  \(port.name)\(port.online ? "" : "  (offline)")")
            }
        }
    }

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
