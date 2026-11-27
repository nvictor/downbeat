import ApplicationServices
import Foundation

/// What a split does with notes that cross the split point.
public enum CrossingNotes: String, CaseIterable, Sendable {
    case keep, shorten, split

    var buttonTitle: String { rawValue.capitalized }
}

extension LogicApp {
    /// Splits the one region that matches at the first beat of a bar inside it.
    /// `notes` answers Logic Pro when notes cross that point.
    public func splitRegion(_ reference: RegionReference, atBar bar: Int, notes: CrossingNotes) throws {
        let source = try select(reference, anyPosition: true)
        guard bar > source.startBar, bar < source.endBar else {
            throw DownbeatError("""
                Bar \(bar) is not inside the region, which covers bars \(source.startBar) to \(source.endBar).
                """)
        }
        let count = try regions(on: source.track).count
        try movePlayhead(toBar: bar)

        try undoingOnFailure { step in
            try step {
                try chooseInTracksEditMenu(["Split", "Regions at Playhead"])
                try wait("the region to be split") { () -> Bool? in
                    if let question = dialog(saying: "Notes Crossing Split Point") {
                        try press(notes.buttonTitle, role: kAXRadioButtonRole, in: question)
                        try press("OK", role: kAXButtonRole, in: question)
                    }
                    return try regions(on: source.track).count == count + 1 && dialogs.isEmpty ? true : nil
                }
            }
            guard try regions(on: source.track).contains(where: {
                $0.help.flatMap(Self.position).map { $0.startBar == bar && $0.startsOnBarLine } == true
            }) else {
                throw DownbeatError("No part starts at bar \(bar).")
            }
        }
    }

    /// Joins the one region that matches with the next region of its track, when the two touch.
    public func joinRegion(_ reference: RegionReference) throws -> Placement {
        let first = try select(reference, anyPosition: true)
        let number = Self.trackParts(first.track).number
        let following = try regionSummaries()
            .filter { $0.trackNumber == number && ($0.startBar ?? 0) > first.startBar }
            .compactMap(\.startBar)
            .min()
        guard let next = following, next <= first.endBar else {
            throw DownbeatError("No region follows without a gap. Nothing was changed.")
        }
        let count = try regions(on: first.track).count
        let name = try regionName(startingIn: first.startBar, on: first.track)
        try select(regionStartingAt: next, on: first.track)
        let second = try selectedPlacement()
        try addToSelection(regionStartingAt: first.startBar, on: first.track)

        try undoingOnFailure { step in
            try step {
                try chooseInTracksEditMenu(["Bounce or Join", "Join"])
                try wait("the regions to be joined", seconds: 30) { () -> Bool? in
                    // Audio that does not continue the same recording needs a new file.
                    if let question = dialogs.first {
                        try? press("Cancel", role: kAXButtonRole, in: question)
                        throw DownbeatError("""
                            Logic Pro asks a question before joining these regions, probably to create a \
                            new audio file. Join them by hand.
                            """)
                    }
                    return try regions(on: first.track).count == count - 1 ? true : nil
                }
            }
        }
        let joined = Placement(
            track: first.track, startBar: first.startBar, endBar: max(first.endBar, second.endBar)
        )
        // Logic Pro may name the joined region after something else.
        try restoreName(name, of: joined, after: "joined")
        return joined
    }

    private func dialog(saying text: String) -> AXElement? {
        dialogs.first { dialog in
            dialog.first {
                $0.role == kAXStaticTextRole && $0.string(kAXValueAttribute) == text
            } != nil
        }
    }

    private func press(_ title: String, role: String, in dialog: AXElement) throws {
        guard let button = dialog.first(where: { $0.role == role && $0.title == title }) else {
            throw DownbeatError("The \(title) button was not found. Answer the dialog by hand.")
        }
        try button.perform(kAXPressAction)
    }
}
