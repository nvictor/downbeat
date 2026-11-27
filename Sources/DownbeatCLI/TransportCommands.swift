import ArgumentParser
import DownbeatKit

struct Play: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start playback.")

    func run() throws {
        try LogicApp().play()
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop playback or recording.")

    func run() throws {
        try LogicApp().stop()
    }
}

struct Record: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start recording. End it with `downbeat stop`."
    )

    @OptionGroup var target: ProjectOption

    func run() throws {
        try target.app().record()
    }
}
