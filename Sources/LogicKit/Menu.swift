import ApplicationServices

extension LogicApp {
    /// Chooses a menu item by its English titles, for example `["File", "Import", "MIDI File…"]`.
    func choose(_ path: [String]) throws {
        guard let bar = root.element(kAXMenuBarAttribute),
              let top = bar.children.first(where: { $0.title == path.first }) else {
            throw LogicError("Menu \(path.first ?? "") not found.")
        }
        var item = top
        for title in path.dropFirst() {
            guard let next = item.children.flatMap(\.children).first(where: { $0.title == title }) else {
                throw LogicError("Menu item \(title) not found.")
            }
            item = next
        }
        // Press the item without opening its menu: an opened menu stays up behind the
        // resulting panel and swallows its keyboard input.
        // A menu item that opens a modal panel can report failure although it ran,
        // so callers confirm the outcome themselves.
        _ = AXUIElementPerformAction(item.raw, kAXPressAction as CFString)
    }
}
