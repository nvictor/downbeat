import ApplicationServices
import AVFoundation
import Foundation

extension LogicApp {
    /// Imports an audio file onto an audio track, starting at a bar whose range is free.
    public func importAudio(from url: URL, track reference: String, bar: Int) throws -> TrackSummary {
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        guard let file = try? AVAudioFile(forReading: url) else {
            throw DownbeatError("\(url.path) is not a readable audio file.")
        }
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        let track = try selectTrack(reference)
        try requireAudioStrip(named: track.name)
        try movePlayhead(toBar: bar)
        let status = try status()
        guard let tempo = status.tempo, let signature = status.signature,
              let bars = Self.bars(covering: seconds, tempo: tempo, signature: signature) else {
            throw DownbeatError("The tempo and meter could not be read.")
        }
        // Estimated from the tempo and meter at the start bar.
        try requireFree(bars: bar..<(bar + bars), onTrack: track.number)
        func count() throws -> Int {
            try tracks().first { Self.trackParts($0.name).number == track.number }?.regions.count ?? 0
        }
        let before = try count()
        let panel = try FilePanel.open(in: self) {
            try choose(["File", "Import", "Audio File…"])
        }
        do {
            try panel.goTo(url.resolvingSymlinksInPath().path)
            try panel.confirm()
        } catch {
            panel.cancel()
            throw error
        }
        try wait("the audio region on \(track.name)", seconds: 60) { try count() == before + 1 ? true : nil }
        return track
    }

    /// Bounces one track to a WAVE file, with the other settings Logic Pro last used.
    /// Selects the track.
    public func exportAudio(track reference: String, to url: URL) throws {
        guard url.pathExtension.lowercased() == "wav" else { throw DownbeatError("The output must end in .wav.") }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw DownbeatError("\(url.path) already exists.")
        }
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        _ = try selectTrack(reference)
        let files = FileManager.default
        // The panel names the file itself, so export into an empty folder and move the result.
        let folder = files.temporaryDirectory.appendingPathComponent("downbeat-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        let panel = try FilePanel.open(in: self) {
            try choose(["File", "Export", "1 Track as Audio File…"])
        }
        do {
            try panel.goTo(folder.resolvingSymlinksInPath().path)
            try panel.requirePopUp("WAVE", among: ["AIFF", "CAF"])
            try panel.confirm()
        } catch {
            panel.cancel()
            throw error
        }
        // Logic Pro shows a progress window while it writes.
        var last = -1
        let result = try wait("the exported audio", seconds: 600) { () -> URL? in
            guard dialogs.isEmpty,
                  let file = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                      .first(where: { $0.pathExtension.lowercased() == "wav" }) else { return nil }
            let size = (try? files.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            defer { last = size }
            guard size > 44, size == last else {
                Thread.sleep(forTimeInterval: 0.5)
                return nil
            }
            return file
        }
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.moveItem(at: result, to: url)
    }

    /// Whole bars that `seconds` of audio covers at a tempo and meter.
    static func bars(covering seconds: Double, tempo: Double, signature: String) -> Int? {
        let parts = signature.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0, tempo > 0 else { return nil }
        let quartersPerBar = parts[0] * 4 / parts[1]
        // A hair under a bar line still ends there.
        return max(1, Int((seconds * tempo / 60 / quartersPerBar - 1e-6).rounded(.up)))
    }
}
