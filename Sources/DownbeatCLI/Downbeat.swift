import ArgumentParser

@main
struct Downbeat: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "downbeat",
        abstract: "Control Logic Pro from the command line.",
        subcommands: [
            Check.self, Inspect.self, StatusCommand.self, Project.self, Tempo.self,
            TrackCommands.self, Region.self, NoteCommands.self,
        ]
    )
}
