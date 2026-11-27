import ArgumentParser

@main
struct Downbeat: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "downbeat",
        abstract: "Control Logic Pro from the command line.",
        version: "0.1.0",
        subcommands: [
            Check.self, Inspect.self, StatusCommand.self, Project.self, Tempo.self,
            TrackCommands.self, Region.self, NoteCommands.self, MIDICommands.self, MixerCommands.self,
            MarkerCommands.self, PluginCommands.self, AudioCommands.self,
            Play.self, Stop.self, Record.self,
        ]
    )
}
