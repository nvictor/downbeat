import Foundation

/// A random value that depends only on its key, so one edit never moves another note.
/// FNV-1a of the key, mixed by one SplitMix64 step. `Hasher` is seeded per process.
func stableRandom(_ key: String) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in key.utf8 {
        hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
    }
    var value = hash &+ 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
}

extension ResolvedArrangement {
    /// Applies the rules to the straight hits. When several rules match a hit, the last wins.
    mutating func apply(_ rules: [Arrangement.HumanizeRule]) throws {
        guard !rules.isEmpty else { return }
        let scopes = try rules.map { rule in
            (rule: rule, articulations: try drumMap.expand(rule.articulations), bars: rule.bars.flatMap(BarRange.init))
        }
        for s in sections.indices {
            let section = sections[s]
            for p in section.parts.indices {
                let part = section.parts[p]
                let hits: [Hit] = part.hits.compactMap { hit in
                    let bar = part.bar + (hit.tick + gridTolerance) / section.meter.barTicks
                    guard let rule = scopes.last(where: {
                        $0.rule.section == section.name
                            && ($0.rule.part == nil || $0.rule.part == part.clip)
                            && ($0.bars?.bars.contains(bar) ?? true)
                            && ($0.articulations.isEmpty || hit.articulation.map($0.articulations.contains) == true)
                    })?.rule else { return hit }
                    return Self.humanize(hit, rule, source: part.source, length: part.length)
                }
                sections[s].parts[p].hits = Self.separate(hits)
            }
        }
    }

    private static func humanize(_ hit: Hit, _ rule: Arrangement.HumanizeRule, source: String, length: Int) -> Hit? {
        func random(_ purpose: String) -> UInt64 {
            stableRandom("\(rule.seed)|\(source)|\(hit.pitch)|\(hit.tick)|\(purpose)")
        }
        func offset(_ purpose: String, _ limit: Int) -> Int {
            limit == 0 ? 0 : Int(random(purpose) % UInt64(2 * limit + 1)) - limit
        }
        if !hit.accent && rule.drop > 0 && Double(random("drop") >> 11) * 0x1p-53 < rule.drop { return nil }
        var result = hit
        // The grace and main strokes move together and stay inside the part.
        let limit = Int(rule.timing * Double(ticksPerQuarter))
        let earliest = -(hit.tick - (hit.flam?.offset ?? 0))
        let latest = length - hit.tick - hit.length
        result.tick += min(max(offset("timing", limit), earliest), latest)
        if !hit.accent {
            let change = offset("velocity", rule.velocity)
            result.velocity = min(max(hit.velocity + change, 1), 127)
            if let flam = hit.flam {
                var grace = min(max(flam.velocity + change, 1), 127)
                if flam.velocity < hit.velocity { grace = min(grace, max(result.velocity - 1, 1)) }
                result.flam?.velocity = grace
            }
        }
        return result
    }

    /// Shortens strokes that jitter made overlap the next one of the same pitch.
    private static func separate(_ hits: [Hit]) -> [Hit] {
        var result = hits.sorted { ($0.pitch, $0.tick) < ($1.pitch, $1.tick) }
        for index in result.indices.dropLast() where result[index].pitch == result[index + 1].pitch {
            let next = result[index + 1].tick - (result[index + 1].flam?.offset ?? 0)
            result[index].length = max(min(result[index].length, next - result[index].tick), 1)
        }
        return result.sorted { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }
    }
}

extension Arrangement {
    /// Stores a rule, replacing the one with the same scope. Returns false when nothing changes.
    public mutating func setHumanize(_ rule: HumanizeRule) -> Bool {
        if let index = humanize.firstIndex(where: { $0.hasSameScope(as: rule) }) {
            if humanize[index] == rule { return false }
            humanize.remove(at: index)
        }
        humanize.append(rule)
        return true
    }

    /// Removes the rules of one section, or the one part of it. Returns how many.
    public mutating func clearHumanize(section: String, part: String? = nil) -> Int {
        let before = humanize.count
        humanize.removeAll { $0.section == section && (part == nil || $0.part == part) }
        return before - humanize.count
    }
}
