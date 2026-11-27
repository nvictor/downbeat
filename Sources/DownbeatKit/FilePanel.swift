import AppKit
import ApplicationServices

/// A standard open or save panel owned by Logic Pro.
struct FilePanel {
    let app: LogicApp
    let window: AXElement

    /// Runs `trigger` and returns the panel it opens.
    static func open(in app: LogicApp, after trigger: () throws -> Void) throws -> FilePanel {
        let existing = app.root.windows
        try trigger()
        let window = try wait("the file panel") {
            app.root.windows.first { candidate in
                !existing.contains { $0.isSame(as: candidate) }
                    && candidate.first { $0.identifier == "OKButton" } != nil
            }
        }
        return FilePanel(app: app, window: window)
    }

    /// Opens "Go to Folder", enters `path` and confirms it.
    func goTo(_ path: String) throws {
        // The panel drops keys sent while it is still appearing.
        Thread.sleep(forTimeInterval: 1)
        try app.sendKey(Key.g, using: ["command down", "shift down"])
        let sheet = try wait("the Go to Folder sheet") { goToSheet }
        let field = try wait("the path field") { sheet.first { $0.identifier == "PathTextField" } }
        try field.set(kAXValueAttribute, to: path as CFString)
        try wait("the path to be accepted") { field.string(kAXValueAttribute) == path ? true : nil }
        // The completion list updates after the value, so give it a moment.
        Thread.sleep(forTimeInterval: 0.4)
        try app.sendKey(Key.returnKey)
        try wait("the Go to Folder sheet to close") { goToSheet == nil ? true : nil }
    }

    func setName(_ name: String) throws {
        let field = try wait("the file name field") { window.first { $0.identifier == "saveAsNameTextField" } }
        try field.set(kAXValueAttribute, to: name as CFString)
        try wait("the file name to be accepted") { field.string(kAXValueAttribute) == name ? true : nil }
    }

    /// Sets the pop-up menu that offers `title` and one of `others`.
    func requirePopUp(_ title: String, among others: [String]) throws {
        let popUp = window.first { element in
            element.role == kAXPopUpButtonRole
                && ([title] + others).contains(element.string(kAXValueAttribute) ?? "")
        }
        guard let popUp else { throw DownbeatError("The \(title) setting was not found in the panel.") }
        if popUp.string(kAXValueAttribute) == title { return }
        try popUp.perform(kAXPressAction)
        let item = try wait("the \(title) menu item", seconds: 3) {
            popUp.first(maxDepth: 3) { $0.role == kAXMenuItemRole && $0.title == title }
        }
        try item.perform(kAXPickAction)
        try wait("\(title) to be chosen") { popUp.string(kAXValueAttribute) == title ? true : nil }
    }

    func confirm() throws {
        let button = try wait("the confirm button to be enabled") {
            window.first { $0.identifier == "OKButton" && $0.bool(kAXEnabledAttribute) != false }
        }
        try button.perform(kAXPressAction)
        try wait("the file panel to close") {
            app.root.windows.contains { $0.isSame(as: window) } ? nil : true
        }
    }

    func cancel() {
        guard app.root.windows.contains(where: { $0.isSame(as: window) }) else { return }
        try? window.first { $0.identifier == "CancelButton" }?.perform(kAXPressAction)
    }

    private var goToSheet: AXElement? {
        window.children.first { $0.identifier == "GoToWindow" }
    }
}
