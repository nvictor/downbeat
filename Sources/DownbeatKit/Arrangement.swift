import ApplicationServices

public struct Region: Codable, Sendable, Equatable {
    public let name: String?
    public let help: String?
    public let value: String?
    public let selected: Bool
}

public struct Track: Codable, Sendable, Equatable {
    public let name: String
    public let regions: [Region]
}

/// Addresses one region. Every part given must match.
public struct RegionReference: Sendable {
    public let name: String?
    public let track: String?
    public let bar: Int?

    public init(name: String?, track: String?, bar: Int?) {
        self.name = name
        self.track = track
        self.bar = bar
    }
}

/// A region with its position taken apart.
public struct RegionSummary: Codable, Sendable, Equatable {
    public let track: String
    public let trackNumber: Int?
    public let name: String
    /// The first and the end bar the region touches. Missing when the position cannot be read.
    public let startBar: Int?
    public let endBar: Int?
    /// False when the region starts or ends inside a bar.
    public let onBarLines: Bool
    public let selected: Bool

    func matches(_ reference: RegionReference) -> Bool {
        if let name = reference.name, name != self.name { return false }
        if let track = reference.track, track != self.track, Int(track) != trackNumber { return false }
        if let bar = reference.bar, bar != startBar { return false }
        return true
    }
}

extension LogicApp {
    public func regionSummaries() throws -> [RegionSummary] {
        try tracks().flatMap { track in
            let parts = Self.trackParts(track.name)
            return track.regions.map { region in
                let position = region.help.flatMap(Self.position)
                return RegionSummary(
                    track: parts.name, trackNumber: parts.number, name: Self.regionName(region.name ?? ""),
                    startBar: position?.startBar, endBar: position?.endBar,
                    onBarLines: position?.onBarLines ?? false, selected: region.selected
                )
            }
        }
    }

    /// Splits a description such as `Track 2 “Bass”`, which gains `, mute` or `, solo` when those are on.
    static func trackParts(_ description: String) -> (number: Int?, name: String) {
        guard let match = description.wholeMatch(of: /Track (\d+) “(.*)”(?:, [^“”]*)?/) else { return (nil, description) }
        return (Int(match.1), String(match.2))
    }

    /// Drops the `, muted` that follows a region name while its track is silenced.
    static func regionName(_ description: String) -> String {
        description.hasSuffix(", muted") ? String(description.dropLast(", muted".count)) : description
    }

    /// Makes the one region that matches the only selected region.
    /// Unless `anyPosition`, the region must start and end on a bar line, as MIDI edits need.
    @discardableResult
    public func select(_ reference: RegionReference, anyPosition: Bool = false) throws -> Placement {
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        let all = try tracks()
        let matches = try regionSummaries().filter { $0.matches(reference) }
        guard let match = matches.first else { throw DownbeatError("No region matches. See `downbeat region list`.") }
        guard matches.count == 1 else {
            throw DownbeatError("\(matches.count) regions match. Narrow it with --region, --track and --bar.")
        }
        guard let bar = match.startBar, anyPosition || match.onBarLines else {
            throw DownbeatError("The region must start and end on a bar line.")
        }
        guard let track = all.first(where: {
            let parts = Self.trackParts($0.name)
            return parts.number == match.trackNumber && parts.name == match.track
        }) else {
            throw DownbeatError("The track \(match.track) was not found.")
        }
        try activate()
        try select(regionStartingAt: bar, on: track.name)
        return try selectedPlacement()
    }

    /// Logic Pro cannot export a region silenced by a mute or a solo; it shows an alert instead.
    public func requireAudibleSelection() throws {
        let silenced = try tracks().flatMap(\.regions).contains {
            $0.selected && $0.name?.hasSuffix(", muted") == true
        }
        if silenced {
            throw DownbeatError("The region is silenced by a mute or a solo, so Logic Pro cannot export it.")
        }
    }

    /// Tracks and regions as exposed by the arrange area. Off-screen items may be missing.
    public func tracks() throws -> [Track] {
        guard let window = projectWindow?.element,
              let contents = window.first(where: {
                  $0.role == kAXGroupRole && $0.string(kAXDescriptionAttribute) == "Tracks contents"
              }) else {
            throw DownbeatError("The Tracks area was not found.")
        }
        return contents.children
            .filter { $0.role == "AXLayoutArea" && $0.string(kAXDescriptionAttribute)?.hasPrefix("Track ") == true }
            .map { lane in
                Track(
                    name: lane.string(kAXDescriptionAttribute) ?? "",
                    regions: lane.children.filter { $0.role == "AXLayoutItem" }.map { item in
                        Region(
                            name: item.string(kAXDescriptionAttribute),
                            help: item.string(kAXHelpAttribute),
                            value: item.string(kAXValueAttribute),
                            selected: item.bool(kAXSelectedAttribute) ?? false
                        )
                    }
                )
            }
    }
}
