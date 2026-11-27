import ArgumentParser
import Foundation
import DownbeatKit

struct Region: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List, export and import MIDI regions.",
        subcommands: [List.self, Export.self, Import.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the visible regions.")

        @Option(help: "Only this track, by name or number.")
        var track: String?

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let regions = try LogicApp().regionSummaries().filter {
                track == nil || $0.track == track || $0.trackNumber == track.flatMap(Int.init)
            }
            if json {
                try printJSON(regions)
                return
            }
            for region in regions {
                let number = region.trackNumber.map(String.init) ?? "?"
                let bars = region.startBar.flatMap { start in region.endBar.map { "bars \(start) to \($0)" } }
                print("\(number)  \(region.track)  \(region.name)  \(bars ?? "off the bar lines")")
            }
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Export a region to a MIDI file.")

        @OptionGroup var options: RegionOptions

        @Option(name: .shortAndLong, help: "New .mid file.")
        var output: String

        func run() throws {
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try LogicApp().exportRegion(options.reference, to: url)
            print(url.path)
        }
    }

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Replace a region with a MIDI file, on the same track and bars.",
            discussion: "Use a file made by `downbeat region export`, so its length matches the region."
        )

        @Argument(help: "Edited .mid file.")
        var input: String

        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption

        func run() throws {
            let source = URL(fileURLWithPath: input).standardizedFileURL
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw ValidationError("\(source.path) does not exist.")
            }
            let app = try target.app()
            let placement = try app.select(options.reference)
            try app.requirePlainRegion()
            try app.importRegion(source, at: placement)
            print("Replaced bars \(placement.startBar) to \(placement.endBar).")
        }
    }
}
