import ArgumentParser

@main
struct Downbeat: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "downbeat",
        abstract: "Work with drum MIDI and control Logic Pro from the command line.",
        version: "0.2.0",
        subcommands: [MIDICommands.self, Logic.self, EZdrummer.self]
    )
}
