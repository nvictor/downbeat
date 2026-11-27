import ArgumentParser
import Foundation
import DownbeatKit
import MIDIKit

struct Region: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List, create, rename, move, duplicate, export, import and delete regions.",
        subcommands: [
            List.self, Create.self, Rename.self, Move.self, Duplicate.self,
            Export.self, Import.self, Delete.self,
        ]
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

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add an empty MIDI region to a track. Does not save the project."
        )

        @Option(help: "Track name or number. Use a software instrument or MIDI track.")
        var track: String

        @Option(help: "Bar where the region starts.")
        var bar: Int

        @Option(help: "Length in bars.")
        var bars = 1

        @Option(help: "Region name. Default: the track name.")
        var name: String?

        @OptionGroup var target: ProjectOption

        func validate() throws {
            if bar < 1 { throw ValidationError("--bar must be 1 or more.") }
            if !(1...999).contains(bars) { throw ValidationError("--bars must be 1 to 999.") }
            do {
                try name.map(LogicApp.checkRegionName)
            } catch {
                throw ValidationError("\(error)")
            }
        }

        func run() throws {
            let app = try target.app()
            let title = try name ?? app.trackName(track)
            try withTemporaryDirectory { directory in
                let placement = try app.createRegion(track: track, bar: bar, bars: bars) { signature in
                    let parts = signature.split(separator: "/").compactMap { Int($0) }
                    guard parts.count == 2, parts[1] > 0 else {
                        throw DownbeatError("The meter \(signature) is not supported.")
                    }
                    let ticks = bars * parts[0] * SMF.emptyRegionResolution * 4 / parts[1]
                    let url = directory.appendingPathComponent("empty.mid")
                    try SMF.emptyRegion(name: title, ticks: ticks).write(to: url)
                    return url
                }
                print("Created \(title), bars \(placement.startBar) to \(placement.endBar).")
            }
        }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rename a region. Does not save the project."
        )

        @Argument(help: "New name.")
        var name: String

        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption

        func validate() throws {
            do {
                try LogicApp.checkRegionName(name)
            } catch {
                throw ValidationError("\(error)")
            }
        }

        func run() throws {
            let region = try target.app().renameRegion(options.reference, to: name)
            let number = region.trackNumber.map(String.init) ?? "?"
            print("\(number)  \(region.track)  \(region.name)")
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move a region to another bar of its track. Does not save the project."
        )

        @OptionGroup var options: RegionOptions

        @Option(help: "Bar where the region will start.")
        var toBar: Int

        @OptionGroup var target: ProjectOption

        func validate() throws {
            if toBar < 1 { throw ValidationError("--to-bar must be 1 or more.") }
        }

        func run() throws {
            let moved = try target.app().moveRegion(options.reference, toBar: toBar)
            print("The region now covers bars \(moved.startBar) to \(moved.endBar).")
        }
    }

    struct Duplicate: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Copy a region to another bar of its track. Does not save the project."
        )

        @OptionGroup var options: RegionOptions

        @Option(help: "Bar where the copy starts.")
        var toBar: Int

        @OptionGroup var target: ProjectOption

        func validate() throws {
            if toBar < 1 { throw ValidationError("--to-bar must be 1 or more.") }
        }

        func run() throws {
            let copy = try target.app().duplicateRegion(options.reference, toBar: toBar)
            print("Copied to bars \(copy.startBar) to \(copy.endBar).")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a region. Does not save the project."
        )

        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption

        func run() throws {
            let removed = try target.app().deleteRegion(options.reference)
            print("Deleted bars \(removed.startBar) to \(removed.endBar).")
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
