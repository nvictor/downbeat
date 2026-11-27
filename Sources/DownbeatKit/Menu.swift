import ApplicationServices
import Foundation

extension LogicApp {
    /// Chooses a menu item by its English titles, for example `["File", "Import", "MIDI File…"]`.
    func choose(_ path: [String]) throws {
        guard let bar = root.element(kAXMenuBarAttribute),
              let top = bar.children.first(where: { $0.title == path.first }) else {
            throw DownbeatError("Menu \(path.first ?? "") not found.")
        }
        var item = top
        for title in path.dropFirst() {
            guard let next = item.children.flatMap(\.children).first(where: { $0.title == title }) else {
                throw DownbeatError("Menu item \(title) not found.")
            }
            item = next
        }
        try press(item, in: top, named: path.joined(separator: " > "))
    }

    /// Picks a submenu item of the Edit menu in the Tracks area, which holds commands
    /// the menu bar lacks, such as Split and Join.
    func chooseInTracksEditMenu(_ path: [String]) throws {
        let name = "Edit > \(path.joined(separator: " > "))"
        guard let area = projectWindow?.element.first(where: {
            $0.role == kAXGroupRole && $0.string(kAXDescriptionAttribute) == "Tracks"
        }), let button = area.first(where: {
            $0.role == "AXMenuButton" && $0.string(kAXDescriptionAttribute) == "Edit"
        }) else {
            throw DownbeatError("The Edit menu of the Tracks area was not found.")
        }
        try activate()
        // Pressing a button that opens a menu can report failure although it ran.
        _ = AXUIElementPerformAction(button.raw, kAXPressAction as CFString)
        let menu = try wait("the \(name) menu", seconds: 5) {
            button.first(maxDepth: 3) { $0.role == kAXMenuRole }
                ?? projectWindow?.element.first { $0.role == kAXMenuRole }
        }
        var item = menu
        for title in path {
            let items = item.role == kAXMenuRole ? item.children : item.children.flatMap(\.children)
            guard let next = items.first(where: { $0.title == title }), next.bool(kAXEnabledAttribute) != false else {
                _ = AXUIElementPerformAction(menu.raw, kAXCancelAction as CFString)
                throw DownbeatError("\(name) is missing or disabled.")
            }
            item = next
        }
        try item.perform(kAXPickAction)
    }

    /// The first item of the Edit menu. Its title changes with the action it would undo.
    func chooseUndo() throws {
        guard let edit = root.element(kAXMenuBarAttribute)?.children.first(where: { $0.title == "Edit" }),
              let item = edit.children.first?.children.first else {
            throw DownbeatError("The Undo menu item was not found.")
        }
        try press(item, in: edit, named: "Edit > Undo")
    }

    private func press(_ item: AXElement, in menuBarItem: AXElement, named name: String) throws {
        if item.bool(kAXEnabledAttribute) == false {
            refresh(menuBarItem)
            guard item.bool(kAXEnabledAttribute) != false else {
                throw DownbeatError("\(name) is disabled. Is a region selected?")
            }
        }
        // Press the item without opening its menu: an opened menu stays up behind the
        // resulting panel and swallows its keyboard input.
        // A menu item that opens a modal panel can report failure although it ran,
        // so callers confirm the outcome themselves.
        _ = AXUIElementPerformAction(item.raw, kAXPressAction as CFString)
    }

    /// Logic Pro updates which items are enabled only when a menu opens, so open it and close it.
    private func refresh(_ menuBarItem: AXElement) {
        _ = AXUIElementPerformAction(menuBarItem.raw, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.3)
        for menu in menuBarItem.children {
            _ = AXUIElementPerformAction(menu.raw, kAXCancelAction as CFString)
        }
        Thread.sleep(forTimeInterval: 0.3)
    }
}
