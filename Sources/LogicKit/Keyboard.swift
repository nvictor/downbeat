import AppKit

enum Key {
    static let s = 1
    static let g = 5
    static let returnKey = 36
}

extension LogicApp {
    /// Sends a key to the front application, only while that is Logic Pro.
    /// Goes through System Events, which needs Automation permission.
    func sendKey(_ key: Int, using modifiers: [String] = []) throws {
        try activate()
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
