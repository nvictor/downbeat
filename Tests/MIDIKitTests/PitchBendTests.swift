import Foundation
import Testing
@testable import MIDIKit

/// A format 0, 480 tick file with pitch bend events on channel 1.
private func file(_ points: [(tick: Int, value: Int)]) -> Data {
    var body: [UInt8] = []
    var last = 0
    for point in points {
        let delta = point.tick - last
        if delta > 127 { body.append(UInt8(0x80 | delta >> 7)) }
        body += [UInt8(delta & 0x7F), 0xE0, UInt8(point.value & 0x7F), UInt8(point.value >> 7)]
        last = point.tick
    }
    body += [0x00, 0xFF, 0x2F, 0x00]
    let header = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
    return Data(header + Array("MTrk".utf8) + [0, 0, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body)
}

private func thin(_ points: [(tick: Int, value: Int)]) throws -> [[Int]] {
    let input = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mid")
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mid")
    defer {
        try? FileManager.default.removeItem(at: input)
        try? FileManager.default.removeItem(at: output)
    }
    try file(points).write(to: input)
    let midi = try MIDIFile(contentsOf: input)
    try midi.thinPitchBend()
    try midi.save(to: output)
    return try SMF(data: Data(contentsOf: output)).events
        .filter { $0.bytes[0] == 0xE0 }
        .map { [$0.tick, Int($0.bytes[1]) | Int($0.bytes[2]) << 7] }
}

/// The spacing Logic Pro exports for a drawn ramp.
private let ramp = [(0, 8192), (8, 8312), (15, 8433), (23, 8553), (30, 8674)]
/// The same ramp after one trip: a point added between each pair.
private let once = [
    (0, 8192), (4, 8252), (8, 8312), (12, 8372), (15, 8433), (19, 8493), (23, 8553), (27, 8613), (30, 8674),
]

@Test func keepsARampAtLogicSpacing() throws {
    #expect(try thin(ramp) == ramp.map { [$0.0, $0.1] })
}

@Test func removesAddedPoints() throws {
    #expect(try thin(once) == ramp.map { [$0.0, $0.1] })
}

@Test func removesPointsAddedByTwoTrips() throws {
    var twice: [(Int, Int)] = []
    for (a, b) in zip(once, once.dropFirst()) {
        twice += [a, ((a.0 + b.0) / 2, (a.1 + b.1) / 2)]
    }
    twice.append(once.last!)
    #expect(try thin(twice) == ramp.map { [$0.0, $0.1] })
}

@Test func keepsSparseAndNonLinearPoints() throws {
    let sparse = [(0, 8192), (240, 8312), (480, 8432)]
    #expect(try thin(sparse) == sparse.map { [$0.0, $0.1] })
    let peak = [(0, 8192), (4, 9000), (8, 8192)]
    #expect(try thin(peak) == peak.map { [$0.0, $0.1] })
}
