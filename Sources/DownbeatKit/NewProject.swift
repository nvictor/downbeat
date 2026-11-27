import AppKit
import ApplicationServices

public struct NewProject: Sendable {
    public let destination: URL
    public let template: URL
    public var tempo: Int?
    public var signature: String?
    /// A menu title from `ProjectSettings.keyTitle`.
    public var key: String?

    public init(destination: URL, template: URL, tempo: Int?, signature: String?, key: String?) {
        self.destination = destination
        self.template = template
        self.tempo = tempo
        self.signature = signature
        self.key = key
    }

    public static var defaultTemplate: URL {
        URL.applicationSupportDirectory.appending(path: "downbeat/Blank.logicx")
    }

    /// Copies a project, leaving out the autosave, backup and undo data of the source.
    public static func copyProject(_ source: URL, to destination: URL) throws {
        let files = FileManager.default
        guard source.pathExtension == "logicx", files.fileExists(atPath: source.path) else {
            throw DownbeatError("\(source.path) is not a .logicx project.")
        }
        guard !files.fileExists(atPath: destination.path) else {
            throw DownbeatError("\(destination.path) already exists.")
        }
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: source, to: destination)
        let alternatives = destination.appending(path: "Alternatives")
        for alternative in (try? files.contentsOfDirectory(at: alternatives, includingPropertiesForKeys: nil)) ?? [] {
            for leftover in ["Autosave", "Project File Backups", "Undo Data.nosync"] {
                try? files.removeItem(at: alternative.appending(path: leftover))
            }
        }
    }

    /// Creates the project, opens it in Logic Pro, applies the settings and saves it.
    public func create() throws {
        try tempo.map(ProjectSettings.checkTempo)
        try signature.map(ProjectSettings.checkSignature)
        guard AXIsProcessTrusted() else {
            throw DownbeatError("Accessibility permission is missing. Run `downbeat check`.")
        }
        // Opening a project closes the current one, so never start with unsaved work.
        if let running = try? LogicApp() {
            guard running.dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
            let unsaved = try LogicApp.unsavedDocuments()
            guard unsaved.isEmpty else {
                throw DownbeatError("Save or close \(unsaved.joined(separator: ", ")) first. Nothing was changed.")
            }
        }
        guard let logic = NSWorkspace.shared.urlForApplication(withBundleIdentifier: LogicApp.bundleIdentifier) else {
            throw DownbeatError("Logic Pro is not installed.")
        }
        try Self.copyProject(template, to: destination)
        try open(destination, with: logic)

        let expected = destination.resolvingSymlinksInPath().path
        let app = try wait("Logic Pro to open \(destination.lastPathComponent)", seconds: 90) { () -> LogicApp? in
            guard let app = try? LogicApp(), let path = app.projectWindow?.path,
                  URL(fileURLWithPath: path).resolvingSymlinksInPath().path == expected,
                  app.dialogs.isEmpty, (try? app.status().tempo) != nil else { return nil }
            return app
        }
        guard tempo != nil || signature != nil || key != nil else { return }

        try app.activate()
        try app.movePlayhead(toBar: 1)
        if let signature { try app.setSignature(signature) }
        if let key { try app.setKey(key) }
        if let tempo { try app.setTempo(tempo) }
        try app.save { isSaved() }
    }

    /// Compares the requested settings with the ones stored in the project.
    private func isSaved() -> Bool {
        let url = destination.appending(path: "Alternatives/000/MetaData.plist")
        guard let data = try? Data(contentsOf: url),
              let stored = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return matches(stored)
    }

    func matches(_ stored: [String: Any]) -> Bool {
        if let tempo, (stored["BeatsPerMinute"] as? NSNumber)?.doubleValue != Double(tempo) { return false }
        if let signature {
            let parts = [stored["SongSignatureNumerator"], stored["SongSignatureDenominator"]]
            if parts.compactMap({ ($0 as? NSNumber)?.stringValue }).joined(separator: "/") != signature {
                return false
            }
        }
        if let key {
            let name = [stored["SongKey"], stored["SongGenderKey"]].compactMap { $0 as? String }
                .joined(separator: " ")
                .replacingOccurrences(of: "#", with: "♯")
            let wanted = key.replacingOccurrences(of: "♭", with: "b")
            if name.caseInsensitiveCompare(wanted) != .orderedSame { return false }
        }
        return true
    }

    private func open(_ project: URL, with application: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", application.path, project.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DownbeatError("Could not open \(project.path).") }
    }
}

extension LogicApp {
    /// Saves until the project stays saved. Logic Pro records some changes a moment after
    /// they show, which marks a freshly saved project as modified again.
    func save(until stored: () -> Bool) throws {
        for _ in 1...4 {
            Thread.sleep(forTimeInterval: 2)
            if try LogicApp.unsavedDocuments().isEmpty && stored() { return }
            // The Save menu item is ignored after a pop-up menu was used, so press Command-S.
            try sendKey(Key.s, using: ["command down"])
        }
        throw DownbeatError("The project did not stay saved. Check it in Logic Pro.")
    }

    /// Names of open projects with unsaved changes. Needs Automation permission.
    static func unsavedDocuments() throws -> [String] {
        let script = NSAppleScript(source: """
            tell application id "\(bundleIdentifier)" to get name of every document whose modified is true
            """)
        var failure: NSDictionary?
        guard let result = script?.executeAndReturnError(&failure), failure == nil else {
            throw DownbeatError("Could not ask Logic Pro about unsaved changes: \(failure?[NSAppleScript.errorMessage] ?? "")")
        }
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }
    }
}
