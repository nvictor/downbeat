import ArgumentParser
import DownbeatKit

struct PluginCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugin",
        abstract: "List, add, remove and bypass the plugins of a track.",
        subcommands: [List.self, Add.self, Remove.self, Bypass.self]
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
                let state = switch plugin.bypassed {
                case true?: "  bypassed"
                case false?: ""
                case nil: "  bypass unknown"
                }
                print("\(plugin.number)  \(plugin.name)\(state)")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add an effect to a track. Does not save the project."
        )

        @Argument(help: "Name or number of the track.")
        var track: String

        @Argument(help: "Plugin name, as in Logic Pro's menu, for example Compressor.")
        var plugin: String

        @Option(help: "Menu title such as Stereo or \"Dual Mono\". Default: the first one.")
        var format: String?

        @OptionGroup var target: ProjectOption

        func run() throws {
            let added = try target.app().addPlugin(plugin, format: format, track: track)
            print("\(added.number)  \(added.name)")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a plugin and its settings from a track. Does not save the project."
        )

        @Argument(help: "Name or number of the track.")
        var track: String

        @Argument(help: "Name or number of the plugin, from `logic plugin list`.")
        var plugin: String

        @OptionGroup var target: ProjectOption

        func run() throws {
            let removed = try target.app().removePlugin(plugin, track: track)
            print("Removed \(removed.name).")
        }
    }

    struct Bypass: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bypass a plugin. Does not save the project."
        )

        @Argument(help: "Name or number of the track.")
        var track: String

        @Argument(help: "Name or number of the plugin, from `logic plugin list`.")
        var plugin: String

        @Flag(help: "Turn the bypass off.")
        var off = false

        @OptionGroup var target: ProjectOption

        func run() throws {
            let changed = try target.app().setBypass(!off, plugin: plugin, track: track)
            print("\(changed.name)  \(changed.bypassed == true ? "bypassed" : "active")")
        }
    }
}
