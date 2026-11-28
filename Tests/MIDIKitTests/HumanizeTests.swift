import Foundation
import Testing
@testable import MIDIKit

private func song() throws -> Arrangement {
    try Arrangement(json: Data("""
        {"version": 1, "tempo": 69, "sections": [{"name": "a", "bars": 4, "parts": [
          {"bar": 1, "bars": 2, "name": "grv", "voices": [
            {"articulation": "ride-bow", "velocity": 90, "gus": "P8"},
            {"articulation": "snare-center", "velocity": 120, "accent": true, "flam": {}, "gus": "P4 O(1,2,4)"}]},
          {"bar": 3, "bars": 2, "name": "grv", "use": "01 grv"}]}]}
        """.utf8))
}

private func rule(_ seed: Int, drop: Double = 0) -> Arrangement.HumanizeRule {
    .init(section: "a", seed: seed, timing: 0.02, velocity: 8, drop: drop)
}

private func hits(_ arrangement: Arrangement) throws -> [[Hit]] {
    try arrangement.resolve().sections[0].parts.map(\.hits)
}

@Test func keepsRandomValuesStable() {
    #expect(stableRandom("") == 0xC3817C016BA4FF30)
    #expect(stableRandom("7|a/01 grv|51|0|timing") == 0x9D04F233A770C08C)
}

@Test func humanizesWithinLimitsAndRepeats() throws {
    var arrangement = try song()
    let straight = try hits(arrangement)
    let added = arrangement.setHumanize(rule(7))
    let repeated = arrangement.setHumanize(rule(7))
    #expect(added && !repeated)
    let once = try hits(arrangement)
    #expect(try once == hits(arrangement))
    #expect(once != straight)
    // Straight hits are unchanged, and a repeated groove sounds the same.
    #expect(try arrangement.resolve(humanized: false).sections[0].parts.map(\.hits) == straight)
    #expect(once[0] == once[1])
    // Jitter can reorder hits that start together, so pair them by pitch.
    func byPitch(_ hits: [Hit]) -> [Hit] { hits.sorted { ($0.pitch, $0.tick) < ($1.pitch, $1.tick) } }
    for (a, b) in zip(byPitch(straight[0]), byPitch(once[0])) {
        #expect(a.pitch == b.pitch)
        #expect(abs(a.tick - b.tick) <= 19)
        #expect(abs(a.velocity - b.velocity) <= 8)
        #expect(b.tick >= (b.flam?.offset ?? 0) && b.tick + b.length <= 7680)
        if a.accent { #expect(a.velocity == b.velocity && a.flam == b.flam) }
    }
    _ = arrangement.setHumanize(rule(8))
    #expect(arrangement.humanize.count == 1)
    #expect(try hits(arrangement) != once)
}

@Test func dropsOnlyWhenAskedAndNeverAccents() throws {
    var arrangement = try song()
    _ = arrangement.setHumanize(rule(7))
    #expect(try hits(arrangement)[0].count == 18)
    _ = arrangement.setHumanize(rule(7, drop: 1))
    #expect(try hits(arrangement)[0].map(\.pitch) == [38, 38])
    let removed = arrangement.clearHumanize(section: "a")
    #expect(removed == 1)
}

@Test func buildsTheSameBytesForTheSameSeed() throws {
    var arrangement = try song()
    _ = arrangement.setHumanize(rule(7))
    let reread = try Arrangement(json: arrangement.json())
    #expect(try arrangement.resolve().clips(per: .section).map(\.data) == reread.resolve().clips(per: .section).map(\.data))
}
