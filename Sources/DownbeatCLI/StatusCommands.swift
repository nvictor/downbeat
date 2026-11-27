import ArgumentParser
import DownbeatKit

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show transport, tempo, meter and key."
    )

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let status = try LogicApp().status()
        if json {
            try printJSON(status)
            return
        }
        let unknown = "?"
        let state = status.recording ? "recording" : status.playing ? "playing" : "stopped"
        print("Project:   \(status.project ?? unknown)")
        print("Transport: \(state)\(status.cycle ? ", cycle on" : "")")
        print("Position:  bar \(status.bar.map(String.init) ?? unknown), beat \(status.beat.map(String.init) ?? unknown)")
        print("Tempo:     \(status.tempo.map { $0.formatted() } ?? unknown)")
        print("Meter:     \(status.signature ?? unknown)")
        print("Key:       \(status.key ?? unknown)")
    }
}

struct Tempo: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read or set the tempo.",
        subcommands: [Get.self, Set.self]
    )

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the tempo at the playhead.")

        func run() throws {
            guard let tempo = try LogicApp().status().tempo else {
                throw ValidationError("The tempo could not be read.")
            }
            print(tempo.formatted())
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set the tempo to a whole number. Does not save the project."
        )

        @Argument var bpm: Int
        @OptionGroup var target: ProjectOption

        func validate() throws {
            guard ProjectSettings.tempoRange.contains(bpm) else {
                throw ValidationError("The tempo must be 5 to 990.")
            }
        }

        func run() throws {
            try target.app().setTempo(bpm)
            print(bpm)
        }
    }
}
