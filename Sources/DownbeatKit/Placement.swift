import ApplicationServices
import Foundation

public struct Placement: Codable, Sendable {
    public let track: String
    /// The first and the end bar the region touches.
    public let startBar: Int
    public let endBar: Int
    /// False when the region starts or ends inside a bar.
    var onBarLines = true

    var bars: Range<Int> { startBar..<endBar }

    /// The same number of bars on the same track, from the start of another bar.
    func moved(toBar bar: Int) -> Placement {
        Placement(track: track, startBar: bar, endBar: bar + endBar - startBar, onBarLines: onBarLines)
    }
}

/// Where a region sits, in the bars it touches.
struct Position: Equatable {
    let startBar: Int
    let endBar: Int
    let startsOnBarLine: Bool
    let endsOnBarLine: Bool

    var onBarLines: Bool { startsOnBarLine && endsOnBarLine }
}

extension LogicApp {
    /// The single selected region.
    public func selectedPlacement() throws -> Placement {
        let selected = try tracks().flatMap { track in
            track.regions.filter(\.selected).map { (track.name, $0) }
        }
        guard selected.count == 1, let (track, region) = selected.first else {
            throw DownbeatError("Select exactly one region.")
        }
        guard let position = region.help.flatMap(Self.position) else {
            throw DownbeatError("The position of the selected region cannot be read.")
        }
        return Placement(
            track: track, startBar: position.startBar, endBar: position.endBar,
            onBarLines: position.onBarLines
        )
    }

    /// Reads help text such as `starts at 5 bars and ends at 6 bars 2 beats ,`.
    static func position(help: String) -> Position? {
        let pattern = /starts at (\d+) bars?([^,]*?)\s+and ends at (\d+) bars?([^,]*),/
        guard let match = help.firstMatch(of: pattern),
              let start = Int(match.1), let end = Int(match.3) else { return nil }
        // Beats, divisions or ticks after a bar number place the point inside that bar.
        let startsOnBarLine = !match.2.contains(where: \.isNumber)
        let endsOnBarLine = !match.4.contains(where: \.isNumber)
        return Position(
            startBar: start, endBar: max(endsOnBarLine ? end : end + 1, start + 1),
            startsOnBarLine: startsOnBarLine, endsOnBarLine: endsOnBarLine
        )
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
        try requireFree(bars: bar..<end, onTrack: track.number)
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
                $0.help.flatMap(Self.position)
                    == Position(startBar: bar, endBar: end, startsOnBarLine: true, endsOnBarLine: true)
            }) else {
                throw DownbeatError("The new region does not cover bars \(bar) to \(end).")
            }
        }
        return target
    }

    /// Copies the one region that matches to another bar of its track, with Copy and Paste,
    /// so everything about the region is kept.
    public func duplicateRegion(_ reference: RegionReference, toBar bar: Int) throws -> Placement {
        let source = try select(reference, anyPosition: true)
        let target = source.moved(toBar: bar)
        try requireFree(bars: target.bars, onTrack: Self.trackParts(source.track).number)
        let count = try regions(on: source.track).count

        // Copy acts on the focused pane, so focus the Tracks area first.
        try select(track: source.track)
        try select(regionStartingAt: source.startBar, on: source.track)
        try choose(["Edit", "Copy"])

        try undoingOnFailure { step in
            try paste(on: target, expecting: count + 1, step: step)
            try requireRegion(at: target)
        }
        return target
    }

    /// Moves the one region that matches to another bar of its track, with Cut and Paste.
    public func moveRegion(_ reference: RegionReference, toBar bar: Int) throws -> Placement {
        let source = try select(reference, anyPosition: true)
        // A region that starts inside the bar still moves, to its first beat.
        if source.startBar == bar, try startsOnBarLine(source) { return source }
        let target = source.moved(toBar: bar)
        // The region may overlap its own old bars.
        try requireFree(
            bars: target.bars, onTrack: Self.trackParts(source.track).number, ignoring: source.startBar
        )
        let count = try regions(on: source.track).count
        let name = try regionName(startingIn: source.startBar, on: source.track)

        // Cut acts on the focused pane, so focus the Tracks area first.
        try select(track: source.track)
        try select(regionStartingAt: source.startBar, on: source.track)
        try undoingOnFailure { step in
            try step {
                try choose(["Edit", "Cut"])
                try wait("the region to be cut") {
                    try regions(on: source.track).count == count - 1 ? true : nil
                }
            }
            try paste(on: target, expecting: count, step: step)
            try requireRegion(at: target)
        }
        // Logic Pro numbers a pasted audio region anew.
        try restoreName(name, of: target, after: "moved")
        return target
    }

    /// Renames the region at `placement` back when Logic Pro gave it another name.
    func restoreName(_ name: String, of placement: Placement, after change: String) throws {
        guard try regionName(startingIn: placement.startBar, on: placement.track) != name else { return }
        do {
            _ = try renameRegion(
                RegionReference(
                    name: nil, track: Self.trackParts(placement.track).number.map(String.init),
                    bar: placement.startBar
                ),
                to: name
            )
        } catch {
            throw DownbeatError("The region was \(change) but has a new name. \(error)")
        }
    }

    func regionName(startingIn bar: Int, on track: String) throws -> String {
        guard let region = try regions(on: track).first(where: {
            $0.help.flatMap(Self.position)?.startBar == bar
        }) else {
            throw DownbeatError("No region starts in bar \(bar) on \(track).")
        }
        return Self.regionName(region.name ?? "")
    }

    /// Throws unless a pasted region starts where it should. One that kept its length
    /// on bar lines must also end where it should.
    private func requireRegion(at target: Placement) throws {
        guard try regions(on: target.track).contains(where: {
            guard let found = $0.help.flatMap(Self.position) else { return false }
            return found.startBar == target.startBar && found.startsOnBarLine
                && (!target.onBarLines || found.endBar == target.endBar)
        }) else {
            throw DownbeatError("The region does not start at bar \(target.startBar).")
        }
    }

    private func startsOnBarLine(_ placement: Placement) throws -> Bool {
        try regions(on: placement.track).contains {
            $0.help.flatMap(Self.position).map {
                $0.startBar == placement.startBar && $0.startsOnBarLine
            } == true
        }
    }

    /// Throws unless no region of the track touches these bars.
    /// `ignoring` is the start bar of a region that does not count.
    func requireFree(bars: Range<Int>, onTrack number: Int?, ignoring: Int? = nil) throws {
        for track in try tracks() where Self.trackParts(track.name).number == number {
            for region in track.regions {
                let name = Self.regionName(region.name ?? "")
                guard let covered = region.help.flatMap(Self.position).map({ $0.startBar..<$0.endBar }) else {
                    throw DownbeatError("The position of \(name) cannot be read, so free space cannot be checked.")
                }
                if let ignoring, covered.lowerBound == ignoring { continue }
                if covered.overlaps(bars) {
                    throw DownbeatError("""
                        \(name) already covers bars \(covered.lowerBound) to \(covered.upperBound) on \
                        \(Self.trackParts(track.name).name).
                        """)
                }
            }
        }
    }

    /// Runs one undoable step, counting it if it changed anything, even when it then failed.
    typealias Step = (() throws -> Void) throws -> Void

    func undoingOnFailure(_ body: (Step) throws -> Void) throws {
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
        guard imported.track != target.track, imported.onBarLines,
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
        let placement = try select(reference, anyPosition: true)
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

    func regions(on track: String) throws -> [Region] {
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
        let starting = lane.children.filter {
            $0.string(kAXHelpAttribute).flatMap(Self.position)?.startBar == bar
        }
        guard let region = starting.first else {
            throw DownbeatError("No region starts in bar \(bar) on \(track).")
        }
        // Regions are picked by bar here, so two in one bar cannot be told apart.
        guard starting.count == 1 else {
            throw DownbeatError("\(starting.count) regions start in bar \(bar) on \(track).")
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

    /// Selects a region as well as the ones already selected.
    func addToSelection(regionStartingAt bar: Int, on track: String) throws {
        let lane = try element(inGroup: "Tracks contents", described: track)
        guard let region = lane.children.first(where: {
            $0.string(kAXHelpAttribute).flatMap(Self.position)?.startBar == bar
        }) else {
            throw DownbeatError("No region starts in bar \(bar) on \(track).")
        }
        if region.bool(kAXSelectedAttribute) != true {
            try region.set(kAXSelectedAttribute, to: kCFBooleanTrue)
        }
        try wait("two regions to be selected") {
            try tracks().flatMap(\.regions).filter(\.selected).count == 2 ? true : nil
        }
    }

    /// Moves the playhead to the first beat of a bar.
    ///
    /// Only bar and beat can be written, so go to the start first: playback leaves divisions
    /// and ticks behind, which would place a paste or an import off the bar line.
    func movePlayhead(toBar bar: Int) throws {
        let transport = try status()
        guard !transport.playing, !transport.recording else {
            throw DownbeatError("Logic Pro is playing. Run `downbeat logic stop` first.")
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
