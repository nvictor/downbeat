import AppKit
import ApplicationServices

public struct Environment: Codable, Sendable {
    public let accessibilityTrusted: Bool
    public let running: Bool
    public let version: String?
    public let language: String?
    public let projectName: String?
    public let projectPath: String?
    public let openDialog: Bool?

    public var problems: [String] {
        var result: [String] = []
        if !accessibilityTrusted {
            result.append("Grant Accessibility in System Settings > Privacy & Security > Accessibility.")
        }
        if !running { result.append("Open Logic Pro.") }
        if let language, !language.hasPrefix("en") { result.append("Only the English UI is supported.") }
        if accessibilityTrusted && running && projectName == nil { result.append("Open a project.") }
        if openDialog == true { result.append("Close the open dialog in Logic Pro.") }
        return result
    }
}

public struct LogicApp {
    public static let bundleIdentifier = "com.apple.logic10"

    let running: NSRunningApplication
    let root: AXElement

    public init() throws {
        guard AXIsProcessTrusted() else {
            throw DownbeatError("Accessibility permission is missing. Run `downbeat check`.")
        }
        guard let running = Self.process else { throw DownbeatError("Logic Pro is not running.") }
        self.running = running
        root = .application(pid: running.processIdentifier)
    }

    private static var process: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    public static func environment() -> Environment {
        let running = process
        let bundle = running?.bundleURL.flatMap { Bundle(url: $0) }
        let app = try? LogicApp()
        let window = app?.projectWindow
        // An app-specific language setting wins over the system one.
        let languages = CFPreferencesCopyAppValue("AppleLanguages" as CFString, bundleIdentifier as CFString) as? [String]
        return Environment(
            accessibilityTrusted: AXIsProcessTrusted(),
            running: running != nil,
            version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
            language: languages?.first ?? Locale.preferredLanguages.first,
            projectName: window.flatMap { $0.path.map { Self.projectName(path: $0) } },
            projectPath: window?.path,
            openDialog: app.map { !$0.dialogs.isEmpty }
        )
    }

    static func projectName(path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// The first window backed by a document, with the document's file path.
    var projectWindow: (element: AXElement, path: String?)? {
        let main = root.element(kAXMainWindowAttribute)
        for window in ([main].compactMap { $0 } + root.windows) {
            if let document = window.string(kAXDocumentAttribute), let url = URL(string: document) {
                return (window, url.path)
            }
        }
        return nil
    }

    /// Windows that block input. Floating editors such as the Event List report the
    /// dialog subrole too, but they can be minimized and are not modal.
    var dialogs: [AXElement] {
        root.windows.filter { window in
            if window.bool(kAXModalAttribute) == true { return true }
            if window.children.contains(where: { $0.role == kAXSheetRole }) { return true }
            let isDialog = window.subrole == kAXDialogSubrole || window.subrole == kAXSystemDialogSubrole
            return isDialog && window.element(kAXMinimizeButtonAttribute) == nil
        }
    }

    /// Throws unless the expected project is in front and no dialog is open.
    public func requireProject(named expected: String) throws {
        let found = projectWindow?.path.map(Self.projectName(path:))
        guard found == expected else {
            throw DownbeatError("Front project is \(found ?? "unknown"), expected \(expected). Nothing was changed.")
        }
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
    }

    /// Activating again while already in front can move keyboard focus away from a sheet.
    func activate() throws {
        guard root.bool(kAXFrontmostAttribute) != true else { return }
        running.activate()
        try? root.set(kAXFrontmostAttribute, to: kCFBooleanTrue)
        try wait("Logic Pro to come to the front") { root.bool(kAXFrontmostAttribute) == true ? true : nil }
    }
}

/// Polls until `probe` returns a value.
@discardableResult
func wait<T>(_ what: String, seconds: Double = 8, _ probe: () throws -> T?) throws -> T {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if let value = try probe() { return value }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw DownbeatError("Timed out waiting for \(what).")
}
