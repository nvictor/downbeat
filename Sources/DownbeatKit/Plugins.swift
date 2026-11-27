import ApplicationServices
import Foundation

public struct Plugin: Codable, Sendable, Equatable {
    /// Place in the channel strip listing, from 1.
    public let number: Int
    public let name: String
    public let bypassed: Bool
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
            if found.bypassed == on { return found }
            try slots[found.number - 1].bypass.perform(kAXPressAction)
            return try wait("the bypass of \(found.name) to change") {
                Self.slots(in: strip).map(\.plugin).first { $0.number == found.number && $0.bypassed == on }
            }
        }
    }

    /// The one plugin with this name or number.
    static func match(_ reference: String, in plugins: [Plugin]) throws -> Plugin {
        let byName = plugins.filter { $0.name.caseInsensitiveCompare(reference) == .orderedSame }
        let matches = byName.isEmpty ? plugins.filter { String($0.number) == reference } : byName
        guard let first = matches.first else {
            throw DownbeatError("No plugin is named or numbered \(reference). See `downbeat plugin list`.")
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

    /// A slot is a group with a bypass checkbox.
    private static func slots(in strip: AXElement) -> [(plugin: Plugin, bypass: AXElement)] {
        let slots = strip.children.compactMap { group -> (String, AXElement)? in
            guard group.role == kAXGroupRole, let name = group.string(kAXDescriptionAttribute),
                  let bypass = group.children.first(where: {
                      $0.role == kAXCheckBoxRole && $0.string(kAXDescriptionAttribute) == "bypass"
                  }) else { return nil }
            return (name, bypass)
        }
        return slots.enumerated().map { index, slot in
            (Plugin(number: index + 1, name: slot.0, bypassed: slot.1.string(kAXValueAttribute) == "1"), slot.1)
        }
    }
}
