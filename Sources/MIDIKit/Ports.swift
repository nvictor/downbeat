import CoreMIDI

/// A CoreMIDI endpoint of this Mac.
public struct MIDIPort: Codable, Sendable, Equatable {
    public enum Direction: String, Codable, Sendable {
        /// Sends data to the Mac: apps read from it.
        case source
        /// Receives data from the Mac: apps write to it.
        case destination
    }

    public let direction: Direction
    public let name: String
    /// False for a known device that is not connected.
    public let online: Bool

    /// Sources first, then destinations, in the system's order.
    public static func all() -> [MIDIPort] {
        let sources = (0..<MIDIGetNumberOfSources()).map { port(MIDIGetSource($0), .source) }
        let destinations = (0..<MIDIGetNumberOfDestinations()).map { port(MIDIGetDestination($0), .destination) }
        return sources + destinations
    }

    private static func port(_ endpoint: MIDIEndpointRef, _ direction: Direction) -> MIDIPort {
        var text: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &text)
        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
        return MIDIPort(
            direction: direction,
            name: text.map { $0.takeRetainedValue() as String } ?? "?",
            online: offline == 0
        )
    }
}
