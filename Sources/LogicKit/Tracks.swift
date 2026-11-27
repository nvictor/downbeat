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
            throw LogicError("No track is named or numbered \(reference). See `logic track list`.")
        }
        guard matches.count == 1 else {
            throw LogicError("\(matches.count) tracks are named \(reference). Use the track number.")
        }
        return first
    }

    public static func checkTrackName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !name.contains(where: \.isNewline) else {
            throw LogicError("A track name cannot be empty or span lines.")
        }
    }

    /// Adds a track after the selected one and returns it.
    public func createTrack(_ type: TrackType) throws -> TrackSummary {
        guard dialogs.isEmpty else { throw LogicError("A dialog is open in Logic Pro. Close it first.") }
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
        guard dialogs.isEmpty else { throw LogicError("A dialog is open in Logic Pro. Close it first.") }
        let track = try Self.match(reference, in: trackSummaries())
        if track.name == name { return track }
        guard let header = try trackHeaders().first(where: { Self.summary($0) == track }),
              let field = header.children.first(where: { $0.role == kAXTextFieldRole }) else {
            throw LogicError("The name of track \(reference) was not found.")
        }
        let editor = try openNameEditor(field, showing: track.name)
        try editor.set(kAXValueAttribute, to: name as CFString)
        try wait("the new name to be accepted") { editor.string(kAXValueAttribute) == name ? true : nil }
        try sendKey(Key.returnKey)
        return try wait("the track to be renamed") {
            try trackSummaries().first { $0.number == track.number && $0.name == name }
        }
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
        throw LogicError("The name editor of \(name) did not open. Nothing was renamed.")
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
            throw LogicError("The Tracks area was not found.")
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
