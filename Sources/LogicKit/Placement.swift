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
            throw LogicError("Select exactly one region.")
        }
        guard let bars = region.help.flatMap(Self.bars) else {
            throw LogicError("The region must start and end on a bar line.")
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
    public func replaceSelectedRegion(with url: URL, at target: Placement) throws {
        let original = try tracks()
        try movePlayhead(toBar: target.startBar)
        try importMIDI(from: url)

        let imported = try selectedPlacement()
        guard imported.track != target.track,
              imported.startBar == target.startBar, imported.endBar == target.endBar else {
            throw LogicError("Imported region is at \(imported), expected bars \(target.startBar) to \(target.endBar). Undo in Logic Pro.")
        }

        try choose(["Edit", "Cut"])
        try wait("the imported region to be cut") {
            try regions(on: imported.track).isEmpty ? true : nil
        }

        try select(regionStartingAt: target.startBar, on: target.track)
        let count = try regions(on: target.track).count
        try choose(["Edit", "Delete"])
        try wait("the original region to be deleted") {
            try regions(on: target.track).count == count - 1 ? true : nil
        }

        try select(track: target.track)
        try movePlayhead(toBar: target.startBar)
        try choose(["Edit", "Paste"])
        try wait("the region to be pasted on \(target.track)") {
            try regions(on: target.track).count == count ? true : nil
        }

        try select(track: imported.track)
        try choose(["Track", "Delete Track"])
        try wait("the extra track to be removed") {
            try tracks().count == original.count ? true : nil
        }
    }

    private func regions(on track: String) throws -> [Region] {
        try tracks().first { $0.name == track }?.regions ?? []
    }

    private func element(inGroup group: String, described description: String) throws -> AXElement {
        guard let container = projectWindow?.element.first(where: {
            $0.role == kAXGroupRole && $0.string(kAXDescriptionAttribute) == group
        }), let found = container.children.first(where: { $0.string(kAXDescriptionAttribute) == description }) else {
            throw LogicError("\(description) was not found in \(group).")
        }
        return found
    }

    private func select(track: String) throws {
        let header = try element(inGroup: "Tracks header", described: track)
        func isSelected() -> Bool { header.bool(kAXSelectedAttribute) == true }
        // Accessibility reports success but changes nothing, so click the header.
        if !isSelected() {
            guard let frame = header.frame else { throw LogicError("\(track) is not on screen.") }
            try click(CGPoint(x: frame.minX + 12, y: frame.midY), on: header)
        }
        try wait("\(track) to be selected") { isSelected() ? true : nil }
    }

    /// Clicks a point, only if it still belongs to `element` and not to a window above it.
    private func click(_ point: CGPoint, on element: AXElement) throws {
        try activate()
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit
        )
        guard let hit, element.first(maxDepth: 2, where: { CFEqual($0.raw, hit) }) != nil else {
            throw LogicError("Something covers the spot to click. Keep hands off keyboard and mouse.")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func select(regionStartingAt bar: Int, on track: String) throws {
        let lane = try element(inGroup: "Tracks contents", described: track)
        guard let region = lane.children.first(where: {
            $0.string(kAXHelpAttribute).flatMap(Self.bars)?.start == bar
        }) else {
            throw LogicError("No region starts at bar \(bar) on \(track).")
        }
        try region.set(kAXSelectedAttribute, to: kCFBooleanTrue)
        try wait("only the original region to be selected") {
            let placement = try? selectedPlacement()
            return placement?.track == track && placement?.startBar == bar ? true : nil
        }
    }

    /// The control bar sliders move one step per write.
    private func movePlayhead(toBar bar: Int) throws {
        for (name, target) in [("beat", 1), ("bar", bar)] {
            guard let slider = projectWindow?.element.first(where: {
                $0.role == kAXSliderRole && $0.string(kAXDescriptionAttribute) == name
            }) else {
                throw LogicError("The playhead \(name) field was not found.")
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
                throw LogicError("Could not move the playhead to \(name) \(target).")
            }
        }
    }
}
