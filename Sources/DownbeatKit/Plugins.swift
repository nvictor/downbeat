import ApplicationServices
import Foundation

public struct Plugin: Codable, Sendable, Equatable {
    /// Place in the signal chain, from 1.
    public let number: Int
    public let name: String
    /// Nil when Logic Pro does not report it reliably.
    public let bypassed: Bool?
}

extension LogicApp {
    /// The instrument and effects of a track, as its channel strip lists them.
    /// Selects the track to show its strip, then selects the previous one again.
    public func plugins(track reference: String) throws -> [Plugin] {
        let previous = try trackSummaries().filter(\.selected)
        let result = try withStrip(of: reference) { strip in Self.slots(in: strip).map(\.plugin) }
        if previous.count == 1, let number = previous[0].number,
           try trackSummaries().first(where: \.selected)?.number != number {
            _ = try selectTrack(String(number))
        }
        return result
    }

    public func setBypass(_ on: Bool, plugin reference: String, track: String) throws -> Plugin {
        try withStrip(of: track) { strip in
            let slots = Self.slots(in: strip)
            let found = try Self.match(reference, in: slots.map(\.plugin))
            guard let bypassed = found.bypassed else {
                throw DownbeatError("""
                    Logic Pro reports no reliable bypass state for the instrument of this track. \
                    Use the Mixer.
                    """)
            }
            if bypassed == on { return found }
            try slots[found.number - 1].bypass.perform(kAXPressAction)
            return try wait("the bypass of \(found.name) to change") {
                Self.slots(in: strip).map(\.plugin).first { $0.number == found.number && $0.bypassed == on }
            }
        }
    }

    /// Adds an effect after the last one, picked by name from Logic Pro's plugin menu.
    /// `format` is a menu title such as `Stereo` or `Dual Mono`; the first one is used when missing.
    public func addPlugin(_ name: String, format: String?, track: String) throws -> Plugin {
        try withStrip(of: track) { strip in
            guard let button = strip.children.first(where: {
                $0.string(kAXDescriptionAttribute) == "audio plug-in"
            }) else {
                throw DownbeatError("The track \(track) takes no audio plugins.")
            }
            let stripName = strip.string(kAXDescriptionAttribute) ?? ""
            let before = Self.slots(in: strip).map(\.plugin)
            try pick(fromMenuOf: button) { menu in
                guard let item = Self.pluginItem(named: name, in: menu) else {
                    throw DownbeatError("Logic Pro offers no plugin named \(name) for this track.")
                }
                let formats = Self.submenuItems(of: item)
                guard !formats.isEmpty else { return item }
                guard let format else { return formats[0] }
                guard let wanted = formats.first(where: {
                    $0.title?.caseInsensitiveCompare(format) == .orderedSame
                }) else {
                    let titles = formats.compactMap(\.title).joined(separator: ", ")
                    throw DownbeatError("\(name) comes as \(titles), not \(format).")
                }
                return wanted
            }
            // A new effect goes to the end of the chain.
            return try wait("\(name) to be added") {
                guard let current = channelStrip(named: stripName) else { return nil }
                let after = Self.slots(in: current).map(\.plugin)
                return after.count == before.count + 1 ? after.last : nil
            }
        }
    }

    /// Removes a plugin with the `No Plug-in` item of its slot. Its settings are lost.
    public func removePlugin(_ reference: String, track: String) throws -> Plugin {
        try withStrip(of: track) { strip in
            let name = strip.string(kAXDescriptionAttribute) ?? ""
            let slots = Self.slots(in: strip)
            let found = try Self.match(reference, in: slots.map(\.plugin))
            guard let button = slots[found.number - 1].group.children.first(where: {
                $0.string(kAXDescriptionAttribute) == "list"
            }) else {
                throw DownbeatError("The menu of \(found.name) was not found.")
            }
            try pick(fromMenuOf: button) { menu in
                guard let item = menu.children.first(where: { $0.title == "No Plug-in" }) else {
                    throw DownbeatError("The menu of \(found.name) has no way to remove it.")
                }
                return item
            }
            try wait("\(found.name) to be removed") {
                channelStrip(named: name).flatMap { Self.slots(in: $0).count == slots.count - 1 ? true : nil }
            }
            return found
        }
    }

    /// Opens the pop-up menu of `button` and picks the item `choose` returns.
    /// Closes the menu when nothing is picked, and any window the pick opens.
    private func pick(fromMenuOf button: AXElement, _ choose: (AXElement) throws -> AXElement) throws {
        let windows = root.windows
        // Pressing a button that opens a menu can report failure although it ran.
        _ = AXUIElementPerformAction(button.raw, kAXPressAction as CFString)
        let menu = try wait("the plugin menu", seconds: 5) {
            projectWindow?.element.first { $0.role == kAXMenuRole }
        }
        do {
            try choose(menu).perform(kAXPickAction)
        } catch {
            _ = AXUIElementPerformAction(menu.raw, kAXCancelAction as CFString)
            throw error
        }
        // A new plugin shows its window a moment later. Close it, so it cannot block other commands.
        func opened() -> AXElement? {
            root.windows.first { window in !windows.contains { $0.isSame(as: window) } }
        }
        if let window = try? wait("a plugin window", seconds: 2, { opened() }) {
            try window.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
            try wait("the plugin window to close", seconds: 3) { opened() == nil ? true : nil }
        }
    }

    /// The menu entry of a plugin: categories hold entries with submenus, plugins hold only formats.
    private static func pluginItem(named name: String, in menu: AXElement) -> AXElement? {
        for item in menu.children {
            let inner = submenuItems(of: item)
            let isCategory = inner.contains { !submenuItems(of: $0).isEmpty }
            if isCategory {
                for submenu in item.children {
                    if let found = pluginItem(named: name, in: submenu) { return found }
                }
            } else if item.title?.caseInsensitiveCompare(name) == .orderedSame {
                return item
            }
        }
        return nil
    }

    private static func submenuItems(of item: AXElement) -> [AXElement] {
        item.children.filter { $0.role == kAXMenuRole }.flatMap(\.children)
    }

    /// The one plugin with this name or number.
    static func match(_ reference: String, in plugins: [Plugin]) throws -> Plugin {
        let byName = plugins.filter { $0.name.caseInsensitiveCompare(reference) == .orderedSame }
        let matches = byName.isEmpty ? plugins.filter { String($0.number) == reference } : byName
        guard let first = matches.first else {
            throw DownbeatError("No plugin is named or numbered \(reference). See `downbeat logic plugin list`.")
        }
        guard matches.count == 1 else {
            throw DownbeatError("\(matches.count) plugins are named \(reference). Use the plugin number.")
        }
        return first
    }

    /// Selects a track and passes on its channel strip from the inspector.
    private func withStrip<T>(of reference: String, _ body: (AXElement) throws -> T) throws -> T {
        let track = try selectTrack(reference)
        try showInspector()
        // The strip follows the selection a moment later, and tracks may share a name.
        Thread.sleep(forTimeInterval: 0.8)
        let strip = try wait("the channel strip of \(track.name)", seconds: 3) { channelStrip(named: track.name) }
        return try body(strip)
    }

    /// The slots in signal order: the instrument first, then the effects.
    /// A slot is a group with a bypass checkbox; accessibility lists them last to first.
    private static func slots(in strip: AXElement) -> [(plugin: Plugin, bypass: AXElement, group: AXElement)] {
        let slots = strip.children.compactMap { group -> (String, AXElement, AXElement)? in
            guard group.role == kAXGroupRole, let name = group.string(kAXDescriptionAttribute),
                  let bypass = group.children.first(where: {
                      $0.role == kAXCheckBoxRole && $0.string(kAXDescriptionAttribute) == "bypass"
                  }) else { return nil }
            return (name, bypass, group)
        }
        return slots.reversed().enumerated().map { index, slot in
            // Logic Pro sometimes names the instrument slot `input`, and then its checkbox
            // shows a state that does not follow the real one.
            let bypassed = slot.0 == "input" ? nil : slot.1.string(kAXValueAttribute) == "1"
            return (Plugin(number: index + 1, name: slot.0, bypassed: bypassed), slot.1, slot.2)
        }
    }
}
