import ApplicationServices
import Foundation

public struct Marker: Codable, Sendable, Equatable {
    public let name: String
    public let bar: Int
    /// True when the marker starts on the first beat of its bar.
    public let onBarLine: Bool
}

extension LogicApp {
    public static func checkMarkerName(_ name: String) throws {
        // Logic Pro replaces `#` with the marker number.
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !name.contains(where: \.isNewline), !name.contains("#") else {
            throw DownbeatError("A marker name cannot be empty, span lines or contain #.")
        }
    }

    /// Adds a named marker on the first beat of a bar that has none.
    public func createMarker(_ name: String, atBar bar: Int) throws -> Marker {
        try Self.checkMarkerName(name)
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        try activate()
        if let existing = try markers().first(where: { $0.bar == bar }) {
            throw DownbeatError("The marker \(existing.name) already sits in bar \(bar). Nothing was changed.")
        }
        try movePlayhead(toBar: bar)
        try choose(["Navigate", "Create Marker"])
        do {
            // Renames the marker at the playhead, in an editor on the marker track.
            Thread.sleep(forTimeInterval: 0.5)
            try choose(["Navigate", "Rename Marker"])
            let editor = try wait("the marker name editor", seconds: 3) { () -> AXElement? in
                guard let focused = root.element(kAXFocusedUIElementAttribute),
                      focused.role == kAXTextFieldRole,
                      focused.isSettable(kAXValueAttribute),
                      focused.string(kAXValueAttribute)?.hasPrefix("Marker") == true else { return nil }
                return focused
            }
            try editor.set(kAXValueAttribute, to: name as CFString)
            try wait("the new name to be accepted") { editor.string(kAXValueAttribute) == name ? true : nil }
            try sendKey(Key.returnKey)
            let wanted = Marker(name: name, bar: bar, onBarLine: true)
            guard try markers().contains(wanted) else {
                throw DownbeatError("The Marker List does not show \(name) at bar \(bar).")
            }
            return wanted
        } catch {
            throw DownbeatError("A marker was created at bar \(bar) but may not be named. \(error)")
        }
    }

    /// Reads the Marker List and closes it, even when it was open before:
    /// while it has focus, Logic Pro disables the marker commands.
    func markers() throws -> [Marker] {
        func list() -> AXElement? {
            root.windows.first { $0.title?.hasSuffix(" - Marker List") == true }
        }
        if list() == nil { try choose(["Navigate", "Open Marker List"]) }
        defer {
            if let window = list() {
                try? window.children.first { $0.subrole == kAXCloseButtonSubrole }?.perform(kAXPressAction)
                _ = try? wait("the Marker List to close", seconds: 3) { list() == nil ? true : nil }
            }
        }
        // Rows fill in a moment after the window shows or a name changes.
        return try wait("the Marker List to be readable") { list().flatMap(Self.rows) }
    }

    /// Every marker of the list, or nil while some are still missing.
    private static func rows(of window: AXElement) -> [Marker]? {
        guard let table = window.first(where: { $0.role == kAXTableRole }),
              let count = window.first(where: { $0.string(kAXDescriptionAttribute) == "Number of Items" })?
                  .string(kAXValueAttribute) else { return nil }
        let markers = table.children.filter { $0.role == kAXRowRole }.compactMap { row -> Marker? in
            let cells = row.children
            // Lock, position, name and length.
            guard cells.count >= 3,
                  let position = cells[1].children.first?.string(kAXDescriptionAttribute),
                  let name = cells[2].children.first?.string(kAXDescriptionAttribute),
                  let parsed = markerPosition(position) else { return nil }
            return Marker(name: name, bar: parsed.bar, onBarLine: parsed.onBarLine)
        }
        // The count reads such as `3 Markers`, without a number when there are none.
        return markers.count == (Int(count.prefix(while: \.isNumber)) ?? 0) ? markers : nil
    }

    /// Reads a position such as `13 1 1 1 `: bar, beat, division and tick.
    static func markerPosition(_ text: String) -> (bar: Int, onBarLine: Bool)? {
        let parts = text.split(separator: " ").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0], parts.dropFirst().allSatisfy { $0 == 1 })
    }
}
