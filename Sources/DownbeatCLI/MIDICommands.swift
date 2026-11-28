import ArgumentParser
import MIDIKit

struct MIDICommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "midi",
        abstract: "Build, inspect and edit drum MIDI, and list MIDI ports. No app is needed.",
        subcommands: [Build.self, Inspect.self, Edit.self, Humanize.self, Ports.self]
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
}
