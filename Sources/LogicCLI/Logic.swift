import ArgumentParser

@main
struct Logic: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logic",
        abstract: "Control Logic Pro from the command line.",
        subcommands: [Check.self, Inspect.self, Spike.self]
    )
}
