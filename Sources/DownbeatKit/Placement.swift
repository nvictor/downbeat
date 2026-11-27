import ApplicationServices
import Foundation

public struct Placement: Codable, Sendable {
    public let track: String
    public let startBar: Int
    public let endBar: Int
}

extension LogicApp {
    /// The single selected region, if it starts and ends on a bar line.
    public func selectedPlacement() throws -> Placement {
        let selected = try tracks().flatMap { track in
            track.regions.filter(\.selected).map { (track.name, $0) }
        }
        guard selected.count == 1, let (track, region) = selected.first else {
            throw DownbeatError("Select exactly one region.")
        }
        guard let bars = region.help.flatMap(Self.bars) else {
            throw DownbeatError("The region must start and end on a bar line.")
        }
        return Placement(track: track, startBar: bars.start, endBar: bars.end)
    }

    static func bars(help: String) -> (start: Int, end: Int)? {
        let pattern = /starts at (\d+) bars?\s+and ends at (\d+) bars?\s*,/
        guard let match = help.firstMatch(of: pattern),
              let start = Int(match.1), let end = Int(match.2) else { return nil }
        return (start, end)
    }

    /// Replaces the selected region with the content of a MIDI file:
    /// import at the same bar, move the new region to the original track, remove the extra track.
    /// If a step fails, the finished ones are undone.
    /// Pass `empty` when the file has no channel events: Logic Pro gives such a region no color.
    public func replaceSelectedRegion(with url: URL, at target: Placement, empty: Bool) throws {
        let trackCount = try tracks().count
        let color = try regionColor()

        try undoingOnFailure { step in
            try movePlayhead(toBar: target.startBar)
            let imported = try importForMove(url, to: target, step: step)

            try select(track: target.track)
            try select(regionStartingAt: target.startBar, on: target.track)
            let count = try regions(on: target.track).count
            try step {
                try choose(["Edit", "Delete"])
                try wait("the original region to be deleted") {
                    try regions(on: target.track).count == count - 1 ? true : nil
                }
            }

            try paste(on: target, expecting: count, step: step)
            try removeTrack(imported.track, leaving: trackCount, step: step)

            // The new region gets the default color, so a custom one cannot be kept.
            try select(regionStartingAt: target.startBar, on: target.track)
            // A region without a color had none to keep.
            let accepted = empty ? [color, Self.noColor] : [color]
            guard color == Self.noColor || (try? wait("the color", seconds: 3, {
                accepted.contains(try regionColor()) ? true : nil
            })) != nil else {
                throw DownbeatError("The region has a custom color (\(color)), which cannot survive a round trip.")
            }
        }
    }

    /// What the inspector reports for a region without channel events.
    private static let noColor = "not set"

    /// Adds a region to a track from a MIDI file that spans `bars` bars of the meter at `bar`.
    /// `file` receives the meter, for example `4/4`, and returns the file to import.
    public func createRegion(
        track reference: String, bar: Int, bars: Int, file: (String) throws -> URL
    ) throws -> Placement {
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        let track = try Self.match(reference, in: trackSummaries())
        let end = bar + bars
        for region in try regionSummaries() where region.trackNumber == track.number {
            guard let start = region.startBar, let stop = region.endBar else {
                throw DownbeatError("\(region.name) does not sit on bar lines, so free space cannot be checked.")
            }
            if start < end && bar < stop {
                throw DownbeatError("\(region.name) already covers bars \(start) to \(stop) on \(track.name).")
            }
        }
        // Logic Pro adds the imported track after the selected one, which keeps the target's number.
        _ = try selectTrack(reference)
        // Logic Pro would paste a MIDI region on an audio track too, where it makes no sound.
        try requireMIDIStrip(named: track.name)
        guard let lane = try tracks().map(\.name).first(where: { Self.trackParts($0).number == track.number }) else {
            throw DownbeatError("The track \(track.name) was not found.")
        }
        let target = Placement(track: lane, startBar: bar, endBar: end)
        // The control bar shows the meter at the playhead.
        try movePlayhead(toBar: bar)
        guard let signature = try status().signature else { throw DownbeatError("The meter could not be read.") }
        let url = try file(signature)
        let trackCount = try tracks().count
        let count = try regions(on: lane).count

        try undoingOnFailure { step in
            let imported = try importForMove(url, to: target, step: step)
            try paste(on: target, expecting: count + 1, step: step)
            try removeTrack(imported.track, leaving: trackCount, step: step)
            guard try regions(on: lane).contains(where: {
                $0.help.flatMap(Self.bars).map { $0 == (bar, end) } == true
            }) else {
                throw DownbeatError("The new region does not cover bars \(bar) to \(end).")
            }
        }
        return target
    }

    /// Runs one undoable step, counting it if it changed anything, even when it then failed.
    private typealias Step = (() throws -> Void) throws -> Void

    private func undoingOnFailure(_ body: (Step) throws -> Void) throws {
        let original = try layout()
        var changes = 0
        do {
            try body { action in
                let before = try layout()
                do {
                    try action()
                } catch {
                    if (try? layout()) != before { changes += 1 }
                    throw error
                }
                changes += 1
            }
        } catch {
            guard changes > 0 else { throw error }
            do {
                try undo(changes)
                guard try layout() == original else { throw DownbeatError("The tracks differ.") }
            } catch let undoError {
                throw DownbeatError("""
                    \(error)
                    Could not restore the project (\(undoError)). Use Undo in Logic Pro.
                    """)
            }
            throw DownbeatError("\(error)\nThe \(changes) finished steps were undone.")
        }
    }

    /// Imports the file onto a new track and cuts the region, ready to be pasted on the target.
    private func importForMove(_ url: URL, to target: Placement, step: Step) throws -> Placement {
        try step { try importMIDI(from: url) }

        let imported = try selectedPlacement()
        guard imported.track != target.track,
              imported.startBar == target.startBar, imported.endBar == target.endBar else {
            throw DownbeatError("""
                Imported region is on \(imported.track), bars \(imported.startBar) to \(imported.endBar), \
                expected bars \(target.startBar) to \(target.endBar).
                """)
        }

        // Cut, Delete and Paste act on the focused pane, so focus the Tracks area first.
        try select(track: imported.track)
        try select(regionStartingAt: imported.startBar, on: imported.track)
        try step {
            try choose(["Edit", "Cut"])
            try wait("the imported region to be cut") {
                try regions(on: imported.track).isEmpty ? true : nil
            }
        }
        return imported
    }

    private func paste(on target: Placement, expecting count: Int, step: Step) throws {
        try select(track: target.track)
        try movePlayhead(toBar: target.startBar)
        try step {
            try choose(["Edit", "Paste"])
            try wait("the region to be pasted on \(target.track)") {
                try regions(on: target.track).count == count ? true : nil
            }
        }
    }

    private func removeTrack(_ track: String, leaving count: Int, step: Step) throws {
        try select(track: track)
        try step {
            try choose(["Track", "Delete Track"])
            try wait("the extra track to be removed") {
                try tracks().count == count ? true : nil
            }
        }
    }

    /// Deletes the one region that matches.
    public func deleteRegion(_ reference: RegionReference) throws -> Placement {
        let placement = try select(reference)
        // Delete acts on the focused pane, so focus the Tracks area first.
        try select(track: placement.track)
        try select(regionStartingAt: placement.startBar, on: placement.track)
        let count = try regions(on: placement.track).count
        try choose(["Edit", "Delete"])
        try wait("the region to be deleted") {
            try regions(on: placement.track).count == count - 1 ? true : nil
        }
        return placement
    }

    /// Track names and region positions, without the selection.
    private func layout() throws -> [[String]] {
        try tracks().map { track in
            [track.name] + track.regions.map { "\($0.name ?? "") \($0.help ?? "")" }
        }
    }

    private func undo(_ count: Int) throws {
        for _ in 0..<count {
            let before = try layout()
            try chooseUndo()
            try wait("Undo to take effect") { try layout() != before ? true : nil }
        }
    }

    private func regions(on track: String) throws -> [Region] {
        try tracks().first { $0.name == track }?.regions ?? []
    }

    private func element(inGroup group: String, described description: String) throws -> AXElement {
        guard let container = projectWindow?.element.first(where: {
            $0.role == kAXGroupRole && $0.string(kAXDescriptionAttribute) == group
        }), let found = container.children.first(where: { $0.string(kAXDescriptionAttribute) == description }) else {
            throw DownbeatError("\(description) was not found in \(group).")
        }
        return found
    }

    /// Every lane of the Tracks area.
    private func lanes() throws -> [AXElement] {
        guard let contents = projectWindow?.element.first(where: {
            $0.role == kAXGroupRole && $0.string(kAXDescriptionAttribute) == "Tracks contents"
        }) else {
            throw DownbeatError("The Tracks area was not found.")
        }
        return contents.children
    }

    /// Clicks the track header, even when selected, which also focuses the Tracks area.
    private func select(track: String) throws {
        let header = try element(inGroup: "Tracks header", described: track)
        func isSelected() -> Bool { header.bool(kAXSelectedAttribute) == true }
        try click(header: header, of: track)
        try wait("\(track) to be selected") { isSelected() ? true : nil }
    }

    func select(regionStartingAt bar: Int, on track: String) throws {
        let lane = try element(inGroup: "Tracks contents", described: track)
        guard let region = lane.children.first(where: {
            $0.string(kAXHelpAttribute).flatMap(Self.bars)?.start == bar
        }) else {
            throw DownbeatError("No region starts at bar \(bar) on \(track).")
        }
        // Selecting adds to the selection, so clear it on every other region first.
        for other in try lanes().flatMap(\.children)
        where other.bool(kAXSelectedAttribute) == true && !other.isSame(as: region) {
            try other.set(kAXSelectedAttribute, to: kCFBooleanFalse)
        }
        // Setting an already selected region again deselects it.
        if region.bool(kAXSelectedAttribute) != true {
            try region.set(kAXSelectedAttribute, to: kCFBooleanTrue)
        }
        try wait("only the original region to be selected") {
            let placement = try? selectedPlacement()
            return placement?.track == track && placement?.startBar == bar ? true : nil
        }
    }

    /// Moves the playhead to the first beat of a bar.
    ///
    /// Only bar and beat can be written, so go to the start first: playback leaves divisions
    /// and ticks behind, which would place a paste or an import off the bar line.
    func movePlayhead(toBar bar: Int) throws {
        let transport = try status()
        guard !transport.playing, !transport.recording else {
            throw DownbeatError("Logic Pro is playing. Run `downbeat stop` first.")
        }
        // While stopped, the stop button goes to the beginning.
        try press("stopButton")
        Thread.sleep(forTimeInterval: 0.3)
        // The control bar sliders move one step per write.
        for (name, target) in [("beat", 1), ("bar", bar)] {
            guard let slider = projectWindow?.element.first(where: {
                $0.role == kAXSliderRole && $0.string(kAXDescriptionAttribute) == name
            }) else {
                throw DownbeatError("The playhead \(name) field was not found.")
            }
            for _ in 0..<2000 {
                guard let current = slider.string(kAXValueAttribute).flatMap(Int.init) else { break }
                if current == target { break }
                try slider.set(kAXValueAttribute, to: target as CFNumber)
                try wait("the playhead to move", seconds: 2) {
                    slider.string(kAXValueAttribute) != String(current) ? true : nil
                }
            }
            guard slider.string(kAXValueAttribute) == String(target) else {
                throw DownbeatError("Could not move the playhead to \(name) \(target).")
            }
        }
    }
}
