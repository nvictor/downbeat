import ApplicationServices
import Foundation

public struct TrackSummary: Codable, Sendable, Equatable {
    public let number: Int?
    public let name: String
    public let selected: Bool
    public let muted: Bool
    public let soloed: Bool
    public let recordEnabled: Bool
}

public enum TrackType: String, CaseIterable, Sendable {
    case instrument, audio, external

    var menuTitle: String {
        switch self {
        case .instrument: "New Software Instrument Track"
        case .audio: "New Audio Track"
        case .external: "New External MIDI Track"
        }
    }
}

extension LogicApp {
    public func trackSummaries() throws -> [TrackSummary] {
        try trackHeaders().map(Self.summary)
    }

    /// The one track with this name or number.
    static func match(_ reference: String, in tracks: [TrackSummary]) throws -> TrackSummary {
        let byName = tracks.filter { $0.name == reference }
        let matches = byName.isEmpty ? tracks.filter { $0.number.map(String.init) == reference } : byName
        guard let first = matches.first else {
            throw DownbeatError("No track is named or numbered \(reference). See `downbeat logic track list`.")
        }
        guard matches.count == 1 else {
            throw DownbeatError("\(matches.count) tracks are named \(reference). Use the track number.")
        }
        return first
    }

    public static func checkTrackName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !name.contains(where: \.isNewline) else {
            throw DownbeatError("A track name cannot be empty or span lines.")
        }
    }

    /// Adds a track after the selected one and returns it.
    public func createTrack(_ type: TrackType) throws -> TrackSummary {
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        let count = try trackHeaders().count
        try activate()
        try choose(["Track", type.menuTitle])
        // Logic Pro selects the track it adds.
        return try wait("the new track") {
            let tracks = try trackSummaries()
            return tracks.count == count + 1 ? tracks.first(where: \.selected) : nil
        }
    }

    public func renameTrack(_ reference: String, to name: String) throws -> TrackSummary {
        try Self.checkTrackName(name)
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        let track = try Self.match(reference, in: trackSummaries())
        if track.name == name { return track }
        guard let header = try trackHeaders().first(where: { Self.summary($0) == track }),
              let field = header.children.first(where: { $0.role == kAXTextFieldRole }) else {
            throw DownbeatError("The name of track \(reference) was not found.")
        }
        let editor = try openNameEditor(field, showing: track.name)
        try editor.set(kAXValueAttribute, to: name as CFString)
        try wait("the new name to be accepted") { editor.string(kAXValueAttribute) == name ? true : nil }
        try sendKey(Key.returnKey)
        return try wait("the track to be renamed") {
            try trackSummaries().first { $0.number == track.number && $0.name == name }
        }
    }

    public func trackName(_ reference: String) throws -> String {
        try Self.match(reference, in: trackSummaries()).name
    }

    /// Selects a track by clicking its header.
    public func selectTrack(_ reference: String) throws -> TrackSummary {
        let (track, header) = try find(reference)
        try click(header: header, of: track.name)
        return try wait("\(track.name) to be selected") {
            try trackSummaries().first { $0.number == track.number && $0.selected }
        }
    }

    public func setMute(_ on: Bool, track reference: String) throws -> TrackSummary {
        // A solo hides the mute state, so the button cannot be trusted.
        guard try !trackSummaries().contains(where: \.soloed) else {
            throw DownbeatError("A track is soloed, which hides mute states. Turn solo off first.")
        }
        return try setButton("Mute", to: on, track: reference) { $0.muted }
    }

    public func setSolo(_ on: Bool, track reference: String) throws -> TrackSummary {
        try setButton("Solo", to: on, track: reference) { $0.soloed }
    }

    private func setButton(
        _ name: String, to on: Bool, track reference: String, state: (TrackSummary) -> Bool
    ) throws -> TrackSummary {
        let (track, header) = try find(reference)
        if state(track) == on { return track }
        guard let button = header.children.first(where: { $0.string(kAXDescriptionAttribute) == name }) else {
            throw DownbeatError("The \(name) button of \(track.name) was not found.")
        }
        // Like the header, the button ignores accessibility presses, so click it.
        try scrollIntoView(button)
        guard let frame = button.frame else { throw DownbeatError("\(track.name) is not on screen.") }
        try click(CGPoint(x: frame.midX, y: frame.midY), on: button)
        return try wait("\(name) of \(track.name) to change") {
            try trackSummaries().first { $0.number == track.number && state($0) == on }
        }
    }

    func find(_ reference: String) throws -> (TrackSummary, AXElement) {
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        let track = try Self.match(reference, in: trackSummaries())
        guard let header = try trackHeaders().first(where: { Self.summary($0) == track }) else {
            throw DownbeatError("The track \(reference) was not found.")
        }
        return (track, header)
    }

    /// Accessibility reports success but changes nothing, so click the header.
    func click(header: AXElement, of track: String) throws {
        try scrollIntoView(header)
        guard let frame = header.frame else { throw DownbeatError("\(track) is not on screen.") }
        try click(CGPoint(x: frame.minX + 12, y: frame.midY), on: header)
    }

    /// Double-clicks a track name until its editor opens.
    ///
    /// Keys typed outside an edit field act as Logic Pro key commands, so nothing is typed:
    /// the caller writes the name into the editor, which is returned only once it is open.
    private func openNameEditor(_ field: AXElement, showing name: String) throws -> AXElement {
        for _ in 1...3 {
            try scrollIntoView(field)
            guard let frame = field.frame else { break }
            try click(CGPoint(x: frame.minX + min(frame.width / 2, 20), y: frame.midY), on: field, count: 2)
            let editor = try? wait("the name editor", seconds: 2) { () -> AXElement? in
                guard let focused = root.element(kAXFocusedUIElementAttribute),
                      focused.role == kAXTextFieldRole,
                      focused.isSettable(kAXValueAttribute),
                      focused.string(kAXValueAttribute) == name else { return nil }
                return focused
            }
            if let editor { return editor }
        }
        throw DownbeatError("The name editor of \(name) did not open. Nothing was renamed.")
    }

    /// Waits until a scrolled element stops moving.
    private func settle(_ element: AXElement) {
        var last = element.frame
        _ = try? wait("scrolling to end", seconds: 2) { () -> Bool? in
            Thread.sleep(forTimeInterval: 0.3)
            defer { last = element.frame }
            return element.frame == last ? true : nil
        }
    }

    /// Scrolls the track list until `element` is inside its visible part.
    private func scrollIntoView(_ element: AXElement) throws {
        var ancestor = element.element(kAXParentAttribute)
        while let current = ancestor, current.role != kAXScrollAreaRole {
            ancestor = current.element(kAXParentAttribute)
        }
        guard let area = ancestor, let visible = area.frame else { return }
        for _ in 0..<200 {
            guard let frame = element.frame else { return }
            // Positive when the element is above the view.
            let distance: CGFloat
            if frame.minY < visible.minY {
                distance = visible.minY - frame.minY
            } else if frame.maxY > visible.maxY {
                distance = visible.maxY - frame.maxY
            } else {
                return
            }
            defer { settle(element) }
            try scroll(area, by: max(-200, min(200, distance.rounded(.awayFromZero))))
            // Stop when the list cannot move further; the click check reports the rest.
            guard (try? wait("scrolling", seconds: 1, { element.frame != frame ? true : nil })) != nil else { return }
        }
    }

    private func trackHeaders() throws -> [AXElement] {
        guard let group = projectWindow?.element.first(where: {
            $0.role == kAXGroupRole && $0.string(kAXDescriptionAttribute) == "Tracks header"
        }) else {
            throw DownbeatError("The Tracks area was not found.")
        }
        return group.children.filter { $0.string(kAXDescriptionAttribute)?.hasPrefix("Track ") == true }
    }

    private static func summary(_ header: AXElement) -> TrackSummary {
        let parts = trackParts(header.string(kAXDescriptionAttribute) ?? "")
        func isOn(_ name: String) -> Bool {
            header.children.contains {
                $0.string(kAXDescriptionAttribute) == name && $0.string(kAXValueAttribute) == "1"
            }
        }
        return TrackSummary(
            number: parts.number, name: parts.name,
            selected: header.bool(kAXSelectedAttribute) == true,
            muted: isOn("Mute"), soloed: isOn("Solo"), recordEnabled: isOn("Record Enable")
        )
    }
}
