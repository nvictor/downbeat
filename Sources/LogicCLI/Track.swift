import ArgumentParser
import LogicKit

extension TrackType: ExpressibleByArgument {}

struct TrackCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "track",
        abstract: "List, create and rename tracks.",
        subcommands: [List.self, Create.self, Rename.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the tracks.")

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let tracks = try LogicApp().trackSummaries()
            if json {
                try printJSON(tracks)
                return
            }
            for track in tracks {
                let flags = [
                    track.selected ? "selected" : nil, track.muted ? "muted" : nil,
                    track.soloed ? "solo" : nil, track.recordEnabled ? "armed" : nil,
                ].compactMap { $0 }
                let number = track.number.map(String.init) ?? "?"
                print(([number, track.name] + (flags.isEmpty ? [] : [flags.joined(separator: ", ")]))
                    .joined(separator: "  "))
            }
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a track after the selected one. Does not save the project."
        )

        @Option(help: "instrument, audio or external (MIDI).")
        var type: TrackType

        @Option(help: "Name of the new track.")
        var name: String?

        @OptionGroup var target: ProjectOption

        func validate() throws {
            do {
                try name.map(LogicApp.checkTrackName)
            } catch {
                throw ValidationError("\(error)")
            }
        }

        func run() throws {
            let app = try target.app()
            var track = try app.createTrack(type)
            if let name, let number = track.number {
                do {
                    track = try app.renameTrack(String(number), to: name)
                } catch {
                    throw LogicError("Track \(number) was created but not renamed. \(error)")
                }
            }
            print("\(track.number.map(String.init) ?? "?")  \(track.name)")
        }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rename a track. Does not save the project."
        )

        @Argument(help: "Current name or number of the track.")
        var track: String

        @Argument(help: "New name.")
        var name: String

        @OptionGroup var target: ProjectOption

        func validate() throws {
            do {
                try LogicApp.checkTrackName(name)
            } catch {
                throw ValidationError("\(error)")
            }
        }

        func run() throws {
            let renamed = try target.app().renameTrack(track, to: name)
            print("\(renamed.number.map(String.init) ?? "?")  \(renamed.name)")
        }
    }
}
