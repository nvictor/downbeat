import ApplicationServices
import Foundation

extension LogicApp {
    /// Exports the selected region with File > Export > Selection as MIDI File.
    public func exportSelection(to url: URL) throws {
        guard url.pathExtension == "mid" else { throw DownbeatError("The output must end in .mid.") }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw DownbeatError("\(url.path) already exists.")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try activate()
        let panel = try FilePanel.open(in: self) {
            try choose(["File", "Export", "Selection as MIDI File…"])
        }
        do {
            try panel.goTo(url.deletingLastPathComponent().resolvingSymlinksInPath().path)
            try panel.setName(url.lastPathComponent)
            try panel.confirm()
        } catch {
            panel.cancel()
            throw error
        }
        try wait("the exported file at \(url.path)") {
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return (size ?? 0) > 0 ? true : nil
        }
    }

    /// Imports a file at a bar and returns the tracks it added.
    public func importMIDI(from url: URL, atBar bar: Int) throws -> [TrackSummary] {
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        let count = try trackSummaries().count
        try activate()
        try movePlayhead(toBar: bar)
        try importMIDI(from: url)
        // Logic Pro selects what it imports; the new tracks are the ones past the old count.
        let tracks = try trackSummaries()
        let selected = try self.tracks().filter { $0.regions.contains(where: \.selected) }
            .compactMap { Self.trackParts($0.name).number }
        let added = tracks.filter { $0.number.map(selected.contains) == true }
        return added.isEmpty ? Array(tracks.dropFirst(count)) : added
    }

    /// Imports with File > Import > MIDI File, declining the file's tempo.
    /// Logic Pro puts the content on a new track.
    public func importMIDI(from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DownbeatError("\(url.path) does not exist.")
        }
        try activate()
        let before = try tracks().count
        let panel = try FilePanel.open(in: self) {
            try choose(["File", "Import", "MIDI File…"])
        }
        do {
            try panel.goTo(url.resolvingSymlinksInPath().path)
            try panel.confirm()
        } catch {
            panel.cancel()
            throw error
        }
        // The tempo question does not always appear.
        if let alert = try? wait("the tempo question", seconds: 3, { tempoAlert }) {
            guard let no = alert.first(where: { $0.role == kAXButtonRole && $0.title == "No" }) else {
                throw DownbeatError("Logic Pro asks about tempo but has no No button. Answer it by hand.")
            }
            try no.perform(kAXPressAction)
        }
        try wait("a new track") { try tracks().count > before ? true : nil }
    }

    private var tempoAlert: AXElement? {
        dialogs.first { dialog in
            dialog.first {
                $0.role == kAXStaticTextRole
                    && $0.string(kAXValueAttribute)?.localizedCaseInsensitiveContains("tempo") == true
            } != nil
        }
    }
}
