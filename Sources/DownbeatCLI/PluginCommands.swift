import ArgumentParser
import DownbeatKit

struct PluginCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugin",
        abstract: "List and bypass the plugins of a track.",
        subcommands: [List.self, Bypass.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List the instrument and effects of a track.",
            discussion: "Selects the track while reading, then restores the selection."
        )

        @Argument(help: "Name or number of the track.")
        var track: String

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let plugins = try LogicApp().plugins(track: track)
            if json {
                try printJSON(plugins)
                return
            }
            if plugins.isEmpty {
                print("No plugins.")
            }
            for plugin in plugins {
                print("\(plugin.number)  \(plugin.name)\(plugin.bypassed ? "  bypassed" : "")")
            }
        }
    }

    struct Bypass: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bypass a plugin. Does not save the project."
        )

        @Argument(help: "Name or number of the track.")
        var track: String

        @Argument(help: "Name or number of the plugin, from `plugin list`.")
        var plugin: String

        @Flag(help: "Turn the bypass off.")
        var off = false

        @OptionGroup var target: ProjectOption

        func run() throws {
            let changed = try target.app().setBypass(!off, plugin: plugin, track: track)
            print("\(changed.name)  \(changed.bypassed ? "bypassed" : "active")")
        }
    }
}
