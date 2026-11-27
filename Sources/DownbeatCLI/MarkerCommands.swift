import ArgumentParser
import DownbeatKit

struct MarkerCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "marker",
        abstract: "Create markers.",
        subcommands: [Create.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a marker at a bar. Does not save the project."
        )

        @Argument(help: "Marker name.")
        var name: String

        @Option(help: "Bar where the marker starts.")
        var bar: Int

        @OptionGroup var target: ProjectOption

        func validate() throws {
            if bar < 1 { throw ValidationError("--bar must be 1 or more.") }
            do {
                try LogicApp.checkMarkerName(name)
            } catch {
                throw ValidationError("\(error)")
            }
        }

        func run() throws {
            let marker = try target.app().createMarker(name, atBar: bar)
            print("\(marker.bar)  \(marker.name)")
        }
    }
}
