import AudioToolbox

struct PitchBendPoint {
    let tick: Int
    let value: Int

    /// Indices of the points that only fill a ramp more densely than `maxSpan` ticks.
    /// A point goes if the kept point before it and the point after it are at most
    /// `maxSpan` apart and it lies on the line between them.
    static func redundant(in points: [PitchBendPoint], maxSpan: Int) -> Set<Int> {
        var result: Set<Int> = []
        guard points.count > 2 else { return result }
        var kept = points[0]
        for index in 1..<points.count - 1 {
            let point = points[index]
            let next = points[index + 1]
            let span = next.tick - kept.tick
            if span > 0, span <= maxSpan,
               (min(kept.value, next.value)...max(kept.value, next.value)).contains(point.value) {
                let slope = Double(next.value - kept.value) / Double(span)
                let expected = Double(kept.value) + slope * Double(point.tick - kept.tick)
                // Ticks are whole numbers, so allow one tick of slack.
                if abs(Double(point.value) - expected) <= abs(slope) + 1 {
                    result.insert(index)
                    continue
                }
            }
            kept = point
        }
        return result
    }
}

extension MIDIFile {
    /// Logic Pro adds points between close pitch bend events, so their number grows on every
    /// round trip. This brings ramps back to the 1/256 note spacing Logic Pro itself draws.
    /// Returns the number of events removed.
    @discardableResult
    public func thinPitchBend() throws -> Int {
        let ticksPerQuarter = Int(try resolution())
        let maxSpan = (ticksPerQuarter + 63) / 64
        var count: UInt32 = 0
        try check(MusicSequenceGetTrackCount(sequence, &count), "MusicSequenceGetTrackCount")
        var removed = 0
        for index in 0..<count {
            var track: MusicTrack?
            try check(MusicSequenceGetIndTrack(sequence, index, &track), "MusicSequenceGetIndTrack")

            // Pitch bends per channel, each with its position among the track's events.
            var channels: [UInt8: [(position: Int, point: PitchBendPoint)]] = [:]
            try forEachEvent(in: track!) { position, beat, type, data, _ in
                guard type == kMusicEventType_MIDIChannelMessage else { return false }
                let message = data.load(as: MIDIChannelMessage.self)
                guard message.status & 0xF0 == 0xE0 else { return false }
                let point = PitchBendPoint(
                    tick: Int((beat * Double(ticksPerQuarter)).rounded()),
                    value: Int(message.data1) | Int(message.data2) << 7
                )
                channels[message.status & 0x0F, default: []].append((position, point))
                return false
            }

            let doomed = Set(channels.values.flatMap { events in
                PitchBendPoint.redundant(in: events.map(\.point), maxSpan: maxSpan).map { events[$0].position }
            })
            guard !doomed.isEmpty else { continue }
            try forEachEvent(in: track!) { position, _, _, _, _ in doomed.contains(position) }
            removed += doomed.count
        }
        return removed
    }
}
