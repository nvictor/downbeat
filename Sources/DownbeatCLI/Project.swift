import ArgumentParser
import Foundation
import DownbeatKit

struct Project: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create, open, save and describe projects.",
        subcommands: [New.self, Open.self, Save.self, Info.self, Template.self]
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

        @Option(help: "A .logicx project to start from. Default: the one set with `downbeat logic project template`.")
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
                    `downbeat logic project template <path.logicx>`.
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

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open a project. Refuses if an open project has unsaved changes."
        )

        @Argument(help: "A .logicx project.")
        var path: String

        func run() throws {
            let url = fileURL(path)
            try LogicApp.open(project: url)
            print(url.path)
        }
    }

    struct Save: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Save the project in front.")

        @OptionGroup var target: ProjectOption

        func run() throws {
            try target.app().saveProject()
            print("Saved.")
        }
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Describe the project in front.")

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let info = try LogicApp().projectInfo()
            if json {
                try printJSON(info)
                return
            }
            print("Name:     \(info.name)")
            print("Path:     \(info.path)")
            print("Modified: \(info.modified ? "yes" : "no")")
            print("Tempo:    \(info.tempo.map { $0.formatted() } ?? "?")")
            print("Meter:    \(info.signature ?? "?")")
            print("Key:      \(info.key ?? "?")")
            print("Tracks:   \(info.tracks)")
            print("Regions:  \(info.regions)")
        }
    }

    struct Template: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show the default template, or set it from a saved project."
        )

        @Argument(help: "A saved .logicx project to keep a copy of. Leave out to show the current template.")
        var path: String?

        @Flag(help: "Replace the current template.")
        var replace = false

        func validate() throws {
            if replace && path == nil { throw ValidationError("--replace needs a path.") }
        }

        func run() throws {
            let destination = NewProject.defaultTemplate
            let files = FileManager.default
            guard let source = path.map(fileURL) else {
                guard files.fileExists(atPath: destination.path) else {
                    throw ValidationError("No template at \(destination.path). Set one with a .logicx path.")
                }
                print(destination.path)
                return
            }
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
