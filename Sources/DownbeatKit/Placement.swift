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
    public func replaceSelectedRegion(with url: URL, at target: Placement) throws {
        let original = try layout()
        let trackCount = try tracks().count
        let color = try regionColor()
        var changes = 0

        /// Runs one undoable step, counting it if it changed anything, even when it then failed.
        func step(_ action: () throws -> Void) throws {
            let before = try layout()
            do {
                try action()
            } catch {
                if (try? layout()) != before { changes += 1 }
                throw error
            }
            changes += 1
        }

        do {
            try movePlayhead(toBar: target.startBar)
            try step { try importMIDI(from: url) }

            let imported = try selectedPlacement()
            guard imported.track != target.track,
                  imported.startBar == target.startBar, imported.endBar == target.endBar else {
                throw DownbeatError("""
                    Imported region is on \(imported.track), bars \(imported.startBar) to \(imported.endBar), \
                    expected bars \(target.startBar) to \(target.endBar).
                    """)
            }

            try step {
                try choose(["Edit", "Cut"])
                try wait("the imported region to be cut") {
                    try regions(on: imported.track).isEmpty ? true : nil
                }
            }

            try select(regionStartingAt: target.startBar, on: target.track)
            let count = try regions(on: target.track).count
            try step {
                try choose(["Edit", "Delete"])
                try wait("the original region to be deleted") {
                    try regions(on: target.track).count == count - 1 ? true : nil
                }
            }

            try select(track: target.track)
            try movePlayhead(toBar: target.startBar)
            try step {
                try choose(["Edit", "Paste"])
                try wait("the region to be pasted on \(target.track)") {
                    try regions(on: target.track).count == count ? true : nil
                }
            }

            try select(track: imported.track)
            try step {
                try choose(["Track", "Delete Track"])
                try wait("the extra track to be removed") {
                    try tracks().count == trackCount ? true : nil
                }
            }

            // The new region gets the default color, so a custom one cannot be kept.
            try select(regionStartingAt: target.startBar, on: target.track)
            guard (try? wait("the color", seconds: 3, { try regionColor() == color ? true : nil })) != nil else {
                throw DownbeatError("The region has a custom color (\(color)), which cannot survive a round trip.")
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

    private func select(track: String) throws {
        let header = try element(inGroup: "Tracks header", described: track)
        func isSelected() -> Bool { header.bool(kAXSelectedAttribute) == true }
        // Accessibility reports success but changes nothing, so click the header.
        if !isSelected() {
            guard let frame = header.frame else { throw DownbeatError("\(track) is not on screen.") }
            try click(CGPoint(x: frame.minX + 12, y: frame.midY), on: header)
        }
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

    /// The control bar sliders move one step per write.
    func movePlayhead(toBar bar: Int) throws {
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
