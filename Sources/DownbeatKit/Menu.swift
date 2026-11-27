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
