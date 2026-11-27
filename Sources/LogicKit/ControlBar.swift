import ApplicationServices
import Foundation

public struct Status: Codable, Sendable {
    public let project: String?
    public let playing: Bool
    public let recording: Bool
    public let cycle: Bool
    public let bar: Int?
    public let beat: Int?
    public let tempo: Double?
    public let signature: String?
    public let key: String?
}

extension LogicApp {
    public func status() throws -> Status {
        guard projectWindow != nil else { throw LogicError("Open a project.") }
        func isOn(_ button: String) throws -> Bool {
            try control { $0.identifier == "controlBar/\(button)" }.string(kAXValueAttribute) == "1"
        }
        func value(_ role: String, _ description: String) -> String? {
            (try? control(role, description))?.string(kAXValueAttribute)
        }
        return Status(
            project: projectWindow?.path,
            playing: try isOn("playButton"),
            recording: try isOn("recordButton"),
            cycle: try isOn("cycleButton"),
            bar: value(kAXSliderRole, "bar").flatMap(Int.init),
            beat: value(kAXSliderRole, "beat").flatMap(Int.init),
            tempo: value(kAXSliderRole, "Tempo").flatMap(Double.init),
            signature: value(kAXPopUpButtonRole, "Time Signature"),
            key: value(kAXPopUpButtonRole, "Key Signature")
        )
    }

    /// Sets a whole-number tempo. The slider moves one step per write.
    public func setTempo(_ tempo: Int) throws {
        try ProjectSettings.checkTempo(tempo)
        let slider = try control(kAXSliderRole, "Tempo")
        func current() throws -> Double {
            guard let value = slider.string(kAXValueAttribute).flatMap(Double.init) else {
                throw LogicError("The tempo could not be read.")
            }
            return value
        }
        for _ in 0...ProjectSettings.tempoRange.upperBound {
            let before = try current()
            if abs(before - Double(tempo)) < 1 { break }
            try slider.set(kAXValueAttribute, to: tempo as CFNumber)
            try wait("the tempo to change", seconds: 2) { try current() != before ? true : nil }
        }
        guard try current() == Double(tempo) else {
            throw LogicError("Could not set the tempo to \(tempo). It is \(try current()).")
        }
    }

    public func setSignature(_ signature: String) throws {
        try ProjectSettings.checkSignature(signature)
        try choose(signature, inPopUp: "Time Signature")
    }

    public func setKey(_ title: String) throws {
        try choose(title, inPopUp: "Key Signature")
    }

    private func choose(_ title: String, inPopUp description: String) throws {
        func popUp() throws -> AXElement { try control(kAXPopUpButtonRole, description) }
        if try popUp().string(kAXValueAttribute) == title { return }
        // Logic Pro rebuilds the control bar after a change, so a first press can go nowhere.
        // Fetch the button again and retry until its menu shows.
        let item = try wait("the \(description) menu") { () -> AXElement? in
            let button = try popUp()
            func item() -> AXElement? {
                button.first(maxDepth: 3) { $0.role == kAXMenuItemRole && $0.title == title }
            }
            if let found = item() { return found }
            try? button.perform(kAXPressAction)
            Thread.sleep(forTimeInterval: 0.5)
            return item()
        }
        try item.perform(kAXPickAction)
        // Away from the start of the project, Logic Pro asks what to change.
        try wait("\(description) to become \(title)") {
            let confirm = dialogs.lazy.compactMap { dialog in
                dialog.first(maxDepth: 3) {
                    $0.role == kAXButtonRole && $0.title?.hasPrefix("Change project") == true
                }
            }.first
            try confirm?.perform(kAXPressAction)
            return try popUp().string(kAXValueAttribute) == title && confirm == nil ? true : nil
        }
    }

    private func control(_ role: String, _ description: String) throws -> AXElement {
        try control { $0.role == role && $0.string(kAXDescriptionAttribute) == description }
    }

    private func control(_ matches: (AXElement) -> Bool) throws -> AXElement {
        guard let found = projectWindow?.element.first(where: matches) else {
            throw LogicError("A control bar item was not found. Show the control bar in Logic Pro.")
        }
        return found
    }
}
