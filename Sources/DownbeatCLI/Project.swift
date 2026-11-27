import ArgumentParser
import Foundation
import DownbeatKit

struct Project: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create projects.",
        subcommands: [New.self, Template.self]
    )

    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a project from a template, set it up, and open it in Logic Pro."
        )

        @Argument(help: "Project name.")
        var name: String

        @Option(help: "Whole number, 5 to 990.")
        var tempo: Int?

        @Option(help: "One of \(ProjectSettings.signatures.joined(separator: ", ")).")
        var signature: String?

        @Option(help: "For example \"A minor\" or \"F# minor\".")
        var key: String?

        @Option(help: "Folder for the project. Default: ~/Music/Logic.")
        var directory: String?

        @Option(help: "A .logicx project to start from. Default: the one set with `downbeat project template`.")
        var template: String?

        func validate() throws {
            if name.isEmpty || name.contains("/") || name.hasPrefix(".") {
                throw ValidationError("The name cannot be empty, contain / or start with a dot.")
            }
            do {
                try tempo.map(ProjectSettings.checkTempo)
                try signature.map(ProjectSettings.checkSignature)
                _ = try key.map(ProjectSettings.keyTitle)
            } catch {
                throw ValidationError("\(error)")
            }
        }

        func run() throws {
            let folder = directory.map(fileURL) ?? URL.musicDirectory.appending(path: "Logic")
            let source = template.map(fileURL) ?? NewProject.defaultTemplate
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw ValidationError("""
                    No template at \(source.path). Save an empty project in Logic Pro once, then run \
                    `downbeat project template <path.logicx>`.
                    """)
            }
            let destination = folder.appending(path: "\(name).logicx")
            try NewProject(
                destination: destination, template: source,
                tempo: tempo, signature: signature, key: key.map(ProjectSettings.keyTitle)
            ).create()
            print(destination.path)
        }
    }

    struct Template: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Keep a copy of a saved project as the default template."
        )

        @Argument(help: "A saved .logicx project.")
        var path: String

        @Flag(help: "Replace the current template.")
        var replace = false

        func run() throws {
            let destination = NewProject.defaultTemplate
            let source = fileURL(path)
            let files = FileManager.default
            if files.fileExists(atPath: destination.path) {
                guard replace else { throw ValidationError("A template exists. Use --replace.") }
                // Copy next to the old one first, so a bad source cannot destroy it.
                let staged = destination.deletingLastPathComponent().appending(path: "Staged.logicx")
                try? files.removeItem(at: staged)
                try NewProject.copyProject(source, to: staged)
                _ = try files.replaceItemAt(destination, withItemAt: staged)
            } else {
                try NewProject.copyProject(source, to: destination)
            }
            print(destination.path)
        }
    }
}

private func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
}
