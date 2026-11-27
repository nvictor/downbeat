import ApplicationServices
import Foundation

public struct TrackVolume: Codable, Sendable, Equatable {
    public let track: String
    public let number: Int?
    /// As Logic Pro shows it, for example `-6.0 dB`.
    public let level: String
}

public struct TrackPan: Codable, Sendable, Equatable {
    public let track: String
    public let number: Int?
    /// -64 (left) to 63 (right), 0 in the middle.
    public let pan: Int
}

extension LogicApp {
    public static let panRange = -64...63
    /// The top step of an audio fader. External MIDI tracks have a 0 to 127 volume instead.
    private static let faderSteps = 233

    /// The loudest level of a Logic Pro fader.
    public static let maximumVolume = 6.0

    /// Sets a track fader to the step nearest to `target` decibels.
    public func setVolume(_ target: Double, track reference: String) throws -> TrackVolume {
        guard target <= Self.maximumVolume else { throw DownbeatError("The volume cannot exceed +6 dB.") }
        let (track, header) = try find(reference)
        guard let slider = header.children.first(where: {
            $0.role == kAXSliderRole && $0.string(kAXDescriptionAttribute) == "Volume"
        }), let top = slider.value(kAXMaxValueAttribute), let bottom = slider.value(kAXMinValueAttribute) else {
            throw DownbeatError("The volume fader of \(track.name) was not found. Show it in the track header.")
        }
        guard slider.string(kAXMaxValueAttribute) == String(Self.faderSteps) else {
            throw DownbeatError("\(track.name) has no fader in dB. External MIDI tracks are not supported.")
        }
        func read() throws -> (step: String, level: Double, text: String) {
            guard let step = slider.string(kAXValueAttribute),
                  let text = slider.string(kAXValueDescriptionAttribute),
                  let level = Self.decibels(text) else {
                throw DownbeatError("The volume of \(track.name) could not be read.")
            }
            return (step, level, text)
        }
        /// The fader moves one step per write, toward the value written.
        func move(up: Bool) throws -> Bool {
            let before = try read().step
            try slider.set(kAXValueAttribute, to: up ? top : bottom)
            return (try? wait("the fader to move", seconds: 1) { try read().step != before ? true : nil }) != nil
        }

        let up = try read().level < target
        for _ in 0..<1000 {
            let previous = try read()
            if previous.level == target || (previous.level > target) == up { break }
            guard try move(up: up) else { break }
            // Step back when the previous position was nearer.
            let current = try read()
            if (current.level > target) == up, abs(previous.level - target) < abs(current.level - target) {
                _ = try move(up: !up)
                break
            }
        }
        return TrackVolume(track: track.name, number: track.number, level: try read().text)
    }

    /// Sets the pan knob of a track header.
    public func setPan(_ pan: Int, track reference: String) throws -> TrackPan {
        guard Self.panRange.contains(pan) else { throw DownbeatError("The pan must be -64 to 63.") }
        let (track, header) = try find(reference)
        // The knob has no description; only its value text names it.
        guard let slider = header.children.first(where: {
            $0.role == kAXSliderRole && $0.string(kAXValueDescriptionAttribute)?.hasSuffix("Pan") == true
        }) else {
            throw DownbeatError("The pan knob of \(track.name) was not found. Show it in the track header.")
        }
        // The knob counts from 0, with the middle at 64.
        let target = pan - Self.panRange.lowerBound
        func current() throws -> Int {
            guard let value = slider.string(kAXValueAttribute).flatMap(Int.init) else {
                throw DownbeatError("The pan of \(track.name) could not be read.")
            }
            return value
        }
        // The knob moves one step per write.
        for _ in 0..<Self.panRange.count {
            let before = try current()
            if before == target { break }
            try slider.set(kAXValueAttribute, to: target as CFNumber)
            try wait("the pan knob to move", seconds: 2) { try current() != before ? true : nil }
        }
        guard try current() == target else {
            throw DownbeatError("Could not set the pan of \(track.name) to \(pan).")
        }
        return TrackPan(track: track.name, number: track.number, pan: pan)
    }

    /// Reads a level such as `+0.0 dB`, `-6.2 dB` or `-∞ dB`.
    static func decibels(_ text: String) -> Double? {
        let number = text.replacingOccurrences(of: "dB", with: "")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "∞", with: "inf")
            .trimmingCharacters(in: .whitespaces)
        return Double(number)
    }
}
