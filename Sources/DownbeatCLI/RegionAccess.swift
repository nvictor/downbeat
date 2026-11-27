import ArgumentParser
import Foundation
import DownbeatKit
import MIDIKit

struct RegionOptions: ParsableArguments {
    @Option(help: "Region name.")
    var region: String?

    @Option(help: "Track name or number.")
    var track: String?

    @Option(help: "Start bar of the region.")
    var bar: Int?

    func validate() throws {
        if region == nil && track == nil && bar == nil {
            throw ValidationError("Name the region with --region, --track or --bar.")
        }
    }

    var reference: RegionReference { RegionReference(name: region, track: track, bar: bar) }
}

struct ProjectOption: ParsableArguments {
    @Option(help: "Name of the project that must be in front. Guards against editing the wrong one.")
    var project: String

    func app() throws -> LogicApp {
        let app = try LogicApp()
        try app.requireProject(named: project)
        return app
    }
}

extension LogicApp {
    /// Selects a region, refuses it if it has settings, and exports it to `url`.
    @discardableResult
    func exportRegion(_ reference: RegionReference, to url: URL) throws -> Placement {
        let placement = try select(reference)
        try requirePlainRegion()
        try requireAudibleSelection()
        try exportSelection(to: url)
        let file = try MIDIFile(contentsOf: url)
        guard try !file.notes().contains(where: { $0.duration <= 0 }) else {
            try? FileManager.default.removeItem(at: url)
            throw DownbeatError("""
                Logic Pro exported a note with no length, which an edit would write back. This follows \
                a split of a crossing note. Fix the note in Logic Pro, or join the parts again.
                """)
        }
        if try file.thinPitchBend() > 0 { try file.save(to: url) }
        return placement
    }

    /// Replaces the selected region with the content of an edited export.
    func importRegion(_ source: URL, at placement: Placement) throws {
        let channels = try SMF(data: Data(contentsOf: source)).channels
        guard channels.count <= 1 else {
            throw DownbeatError("""
                The file uses channels \(channels.sorted().map(String.init).joined(separator: ", ")). \
                Logic Pro changes the color of such a region, so it cannot be replaced. Nothing was changed.
                """)
        }
        try withTemporaryDirectory { directory in
            let prepared = directory.appendingPathComponent("import.mid")
            try MIDIFile.prepareForImport(source, to: prepared)
            try replaceSelectedRegion(with: prepared, at: placement, empty: channels.isEmpty)
        }
    }
}

func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("downbeat-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}
