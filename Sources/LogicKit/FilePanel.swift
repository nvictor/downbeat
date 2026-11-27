import AppKit
import ApplicationServices

private enum Key {
    static let g = 5
    static let returnKey = 36
}

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
        try post(Key.g, using: ["command down", "shift down"])
        let sheet = try wait("the Go to Folder sheet") { goToSheet }
        let field = try wait("the path field") { sheet.first { $0.identifier == "PathTextField" } }
        try field.set(kAXValueAttribute, to: path as CFString)
        try wait("the path to be accepted") { field.string(kAXValueAttribute) == path ? true : nil }
        // The completion list updates after the value, so give it a moment.
        Thread.sleep(forTimeInterval: 0.4)
        try post(Key.returnKey)
        try wait("the Go to Folder sheet to close") { goToSheet == nil ? true : nil }
    }

    func setName(_ name: String) throws {
        let field = try wait("the file name field") { window.first { $0.identifier == "saveAsNameTextField" } }
        try field.set(kAXValueAttribute, to: name as CFString)
        try wait("the file name to be accepted") { field.string(kAXValueAttribute) == name ? true : nil }
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

    /// Sends a key to the front application, only while that is Logic Pro.
    /// Goes through System Events, which needs Automation permission.
    private func post(_ key: Int, using modifiers: [String] = []) throws {
        try app.activate()
        let using = modifiers.isEmpty ? "" : " using {\(modifiers.joined(separator: ", "))}"
        // The front check runs in the same script as the key, so a key never lands in another app.
        let script = NSAppleScript(source: """
            tell application "System Events"
                set frontID to bundle identifier of (first process whose frontmost is true)
                if frontID is not "\(LogicApp.bundleIdentifier)" then
                    error "Logic Pro is not in front. Keep hands off keyboard and mouse."
                end if
                key code \(key)\(using)
            end tell
            """)
        var failure: NSDictionary?
        script?.executeAndReturnError(&failure)
        if let failure {
            throw LogicError("Could not send a key: \(failure[NSAppleScript.errorMessage] ?? failure)")
        }
    }
}
