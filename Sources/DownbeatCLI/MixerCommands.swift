import ArgumentParser
import DownbeatKit

struct MixerCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mixer",
        abstract: "Set mixer values.",
        subcommands: [Volume.self]
    )

    struct Volume: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set the volume of a track. Does not save the project.",
            discussion: "The fader moves in steps, so the level printed can differ slightly."
        )

        @Argument(help: "Name or number of the track.")
        var track: String

        @Option(parsing: .unconditional, help: "Level in dB, up to 6. For example -6, or -inf for silence.")
        var db: Double

        @OptionGroup var target: ProjectOption

        func validate() throws {
            guard db <= LogicApp.maximumVolume else { throw ValidationError("--db cannot exceed 6.") }
        }

        func run() throws {
            let volume = try target.app().setVolume(db, track: track)
            print("\(volume.number.map(String.init) ?? "?")  \(volume.track)  \(volume.level)")
        }
    }
}
