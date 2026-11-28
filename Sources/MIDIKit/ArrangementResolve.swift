import Foundation

/// One drum hit of a resolved part, in ticks from the start of the part.
public struct Hit: Equatable, Sendable {
    public struct Grace: Equatable, Sendable {
        /// Ticks before the main stroke.
        public var offset: Int
        public var velocity: Int
        public var length: Int
    }

    public var tick: Int
    public var length: Int
    public var pitch: Int
    /// Nil for a pitch the drum map does not name.
    public var articulation: String?
    public var velocity: Int
    public var releaseVelocity: Int
    public var accent: Bool
    public var flam: Grace?

    /// The strokes to write: the grace stroke, if any, then the main one.
    func notes(offsetBy start: Int, channel: Int) -> [SMFNote] {
        let main = SMFNote(
            tick: start + tick, length: length, pitch: pitch, velocity: velocity,
            releaseVelocity: releaseVelocity, channel: channel
        )
        guard let flam else { return [main] }
        var grace = main
        grace.tick -= flam.offset
        grace.length = flam.length
        grace.velocity = flam.velocity
        return [grace, main]
    }
}

/// An arrangement with every length, tempo and reference worked out and checked.
public struct ResolvedArrangement: Sendable {
    public struct Part: Sendable {
        public let bar: Int
        public let bars: Int
        public let name: String
        public let clip: String
        /// `section/clip` of the part that holds the voices and notes.
        public let source: String
        /// Length in ticks.
        public let length: Int
        public var hits: [Hit]
    }

    public struct Section: Sendable {
        public let name: String
        public let bars: Int
        public let tempo: Double
        public let meter: Meter
        /// In order of start bar.
        public var parts: [Part]
        /// Bars that no part covers. They play as silence.
        public var emptyBars: [Int] {
            (1...bars).filter { bar in !parts.contains { ($0.bar..<$0.bar + $0.bars).contains(bar) } }
        }
    }

    public var sections: [Section]
    public let channel: Int
    public let drumMap: DrumMap
}

/// Everything wrong with an arrangement, one problem per line.
public struct ArrangementError: Error, CustomStringConvertible {
    public let problems: [String]
    public var description: String {
        let shown = problems.prefix(20).joined(separator: "\n")
        return problems.count > 20 ? "\(shown)\nand \(problems.count - 20) more" : shown
    }
}

let ticksPerQuarter = SMF.clipResolution

/// Quarter notes to ticks.
func ticks(_ quarters: Double) -> Int { Int((quarters * Double(ticksPerQuarter)).rounded()) }

/// Ticks to quarter notes, rounded to 6 decimals.
func quarters(_ ticks: Int) -> Double { (Double(ticks) / Double(ticksPerQuarter) * 1_000_000).rounded() / 1_000_000 }

extension Meter {
    var barTicks: Int { numerator * ticksPerQuarter * 4 / denominator }
    var beatTicks: Int { ticksPerQuarter * 4 / denominator }
}

extension Arrangement {
    /// Checks the whole arrangement and works out every part. With `humanized` false,
    /// the hits are the straight ones that edits work on.
    public func resolve(humanized: Bool = true) throws -> ResolvedArrangement {
        var problems: [String] = []
        let song: PAL?
        do {
            song = try pal.map(PAL.init)
        } catch {
            throw ArrangementError(problems: ["pal: \(error)"])
        }
        let channel = channel ?? 1
        if !(1...16).contains(channel) { problems.append("channel must be 1 to 16") }
        if sections.isEmpty { problems.append("the arrangement has no sections") }

        checkNames(sections.map(\.name), "section", &problems)
        if let song {
            if let tempo, let other = song.tempo, tempo != other { problems.append("tempo differs from the pal tempo") }
            let ids = sections.compactMap(\.id)
            if ids.count != sections.count { problems.append("with pal, every section needs an \"id\"") }
            if Set(ids).count != ids.count { problems.append("two sections share an id") }
            for part in song.distinct where !ids.contains(part.id) {
                problems.append("pal part \(part.id) has no section")
            }
            for id in ids where !song.distinct.contains(where: { $0.id == id }) {
                problems.append("section id \(id) is not in pal")
            }
        }

        // Settings of each section.
        var settings: [(bars: Int, tempo: Double, meter: Meter)] = []
        for section in sections {
            let place = "section \(section.name)"
            let fromSong = song?.distinct.first { $0.id == section.id }?.bars
            if let bars = section.bars, let fromSong, bars != fromSong {
                problems.append("\(place): bars is \(bars) but pal says \(fromSong)")
            }
            var bars = section.bars ?? fromSong ?? 0
            if !(1...999).contains(bars) {
                problems.append("\(place): needs 1 to 999 bars")
                bars = 1
            }
            var tempo = section.tempo ?? song?.tempo ?? self.tempo ?? 0
            if !(5...990).contains(tempo) {
                problems.append("\(place): needs a tempo of 5 to 990")
                tempo = 120
            }
            var meter = song?.meter ?? Meter.common
            if let text = section.meter ?? self.meter {
                if let parsed = Meter(text) {
                    if let fromSong = song?.meter, fromSong != parsed {
                        problems.append("\(place): meter \(parsed) differs from the pal meter \(fromSong)")
                    }
                    meter = parsed
                } else {
                    problems.append("\(place): cannot read meter \"\(text)\"")
                }
            }
            settings.append((bars, tempo, meter))
        }

        // Layout and references.
        var resolved: [ResolvedArrangement.Section] = []
        var cache: [String: [Hit]] = [:]
        for (index, section) in sections.enumerated() {
            let (bars, tempo, meter) = settings[index]
            checkNames(section.parts.map(\.clip), "section \(section.name): part", &problems)
            var parts: [ResolvedArrangement.Part] = []
            var end = 1
            for part in section.parts.sorted(by: { $0.bar < $1.bar }) {
                let place = "\(section.name) / \(part.clip)"
                checkNames([part.name], "\(place): name", &problems)
                guard part.bar >= 1, (1...999).contains(part.bars) else {
                    problems.append("\(place): bar and bars must be 1 or more")
                    continue
                }
                if part.bar + part.bars - 1 > bars {
                    problems.append("\(place): ends after bar \(bars), the end of the section")
                    continue
                }
                if part.bar < end { problems.append("\(place): overlaps the part before it") }
                end = max(end, part.bar + part.bars)

                var source = (section: index, part: part)
                if let use = part.use {
                    if !part.voices.isEmpty || !part.notes.isEmpty {
                        problems.append("\(place): has \"use\", so it cannot have voices or notes")
                    }
                    guard let found = find(use, from: index) else {
                        problems.append("\(place): no part matches \"use\": \"\(use)\"")
                        continue
                    }
                    if found.part.use != nil {
                        problems.append("\(place): \"\(use)\" is itself a reference. Point at its source.")
                        continue
                    }
                    if found.part.bars != part.bars || settings[found.section].meter != meter {
                        problems.append("\(place): \"\(use)\" has a different length or meter")
                        continue
                    }
                    source = found
                }
                let id = "\(sections[source.section].name)/\(source.part.clip)"
                let length = part.bars * meter.barTicks
                let hits: [Hit]
                if let cached = cache[id] {
                    hits = cached
                } else {
                    hits = expand(source.part, meter: meter, id: id, &problems)
                    cache[id] = hits
                }
                parts.append(.init(
                    bar: part.bar, bars: part.bars, name: part.name, clip: part.clip, source: id,
                    length: length, hits: hits
                ))
            }
            resolved.append(.init(name: section.name, bars: bars, tempo: tempo, meter: meter, parts: parts))
        }
        if let song {
            let order = song.distinct.map(\.id)
            let ids = sections.map(\.id)
            resolved = resolved.indices
                .sorted { (order.firstIndex(of: ids[$0] ?? "") ?? 0) < (order.firstIndex(of: ids[$1] ?? "") ?? 0) }
                .map { resolved[$0] }
        }
        checkRules(&problems)
        guard problems.isEmpty else { throw ArrangementError(problems: problems) }
        var result = ResolvedArrangement(sections: resolved, channel: channel, drumMap: drumMap)
        if humanized { try result.apply(humanize) }
        return result
    }

    /// The part a `use` value names, seen from the section at `index`.
    func find(_ use: String, from index: Int) -> (section: Int, part: Part)? {
        let pieces = use.split(separator: "/", maxSplits: 1).map(String.init)
        let section = pieces.count == 2 ? sections.firstIndex { $0.name == pieces[0] } : index
        guard let section, let name = pieces.last,
              let part = sections[section].parts.first(where: { $0.clip == name }) else { return nil }
        return (section, part)
    }

    private func checkNames(_ names: [String], _ what: String, _ problems: inout [String]) {
        var seen: Set<String> = []
        for name in names {
            if name.isEmpty || name.hasPrefix(".") || name.contains(where: { "/\\:".contains($0) || $0.isNewline })
                || name != name.trimmingCharacters(in: .whitespaces) {
                problems.append("\(what) \"\(name)\" cannot be used as a file name")
            }
            if !seen.insert(name.lowercased()).inserted { problems.append("\(what) \"\(name)\" is used twice") }
        }
    }

    private func checkRules(_ problems: inout [String]) {
        for (index, rule) in humanize.enumerated() {
            let place = "humanize rule \(index + 1)"
            guard let section = sections.first(where: { $0.name == rule.section }) else {
                problems.append("\(place): no section \"\(rule.section)\"")
                continue
            }
            if let part = rule.part, !section.parts.contains(where: { $0.clip == part }) {
                problems.append("\(place): no part \"\(part)\" in \(section.name)")
            }
            if let bars = rule.bars, BarRange(bars) == nil { problems.append("\(place): cannot read bars \"\(bars)\"") }
            do { _ = try drumMap.expand(rule.articulations) } catch { problems.append("\(place): \(error)") }
            if !(0...0.03125).contains(rule.timing) {
                problems.append("\(place): timing must be 0 to 0.03125 quarter notes")
            }
            if !(0...126).contains(rule.velocity) { problems.append("\(place): velocity must be 0 to 126") }
            if !(0...1).contains(rule.drop) { problems.append("\(place): drop must be 0 to 1") }
        }
    }

    /// The hits of a part that owns its voices and notes.
    func expand(_ part: Part, meter: Meter, id: String, _ problems: inout [String]) -> [Hit] {
        let place = id.replacingOccurrences(of: "/", with: " / ")
        let length = part.bars * meter.barTicks
        var hits: [(hit: Hit, label: String)] = []
        for (index, voice) in part.voices.enumerated() {
            let label = "\(place), voice \(index + 1)"
            if voice.gus.count > part.bars { problems.append("\(label): has more GUS lines than bars") }
            let lines: [GUS]
            do {
                lines = try voice.gus.map { try GUS($0, meter: meter) }
            } catch {
                problems.append("\(label): \(error)")
                continue
            }
            for placed in notes(of: voice, lines: lines, bars: part.bars, meter: meter) {
                let name = "\(label), bar \(placed.bar) step \(placed.step)"
                if let hit = hit(placed.note, length: length, name, &problems) { hits.append((hit, name)) }
            }
        }
        for (index, note) in part.notes.enumerated() {
            let name = "\(place), note \(index + 1) (beat \(note.beat.formatted()))"
            if let hit = hit(note, length: length, name, &problems) { hits.append((hit, name)) }
        }

        // No two strokes of one pitch may sound at the same time.
        let strokes = hits.flatMap { entry in
            entry.hit.notes(offsetBy: 0, channel: 1).map { (note: $0, label: entry.label) }
        }.sorted { ($0.note.pitch, $0.note.tick) < ($1.note.pitch, $1.note.tick) }
        for (first, second) in zip(strokes, strokes.dropFirst())
        where first.note.pitch == second.note.pitch && second.note.tick < first.note.tick + first.note.length {
            problems.append("\(second.label): overlaps another note of pitch \(second.note.pitch) (\(first.label))")
        }
        return hits.map(\.hit).sorted { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }
    }

    /// A voice written out as notes, with the bar and sixteenth step of each.
    func notes(of voice: Voice, lines: [GUS], bars: Int, meter: Meter) -> [(note: Note, bar: Int, step: Int)] {
        (0..<bars).flatMap { bar in
            lines[bar % lines.count].hits.enumerated().map { count, step in
                let note = Note(
                    articulation: voice.articulations[count % voice.articulations.count],
                    beat: Double(bar) * meter.barQuarters + Double(step - 1) / 4,
                    duration: voice.duration, velocity: voice.velocities[count % voice.velocities.count],
                    accent: voice.accent, flam: voice.flam
                )
                return (note, bar + 1, step)
            }
        }
    }

    private func hit(_ note: Note, length: Int, _ place: String, _ problems: inout [String]) -> Hit? {
        func fail(_ message: String) -> Hit? {
            problems.append("\(place): \(message)")
            return nil
        }
        let pitch: Int
        switch (note.articulation, note.pitch) {
        case let (name?, nil):
            guard let known = drumMap.articulations[name] else {
                return fail("unknown articulation \"\(name)\". Known: \(drumMap.articulations.keys.sorted().joined(separator: ", "))")
            }
            pitch = known
        case let (nil, number?):
            guard (0...127).contains(number) else { return fail("pitch must be 0 to 127") }
            pitch = number
        default:
            return fail("needs either \"articulation\" or \"pitch\"")
        }
        let duration = note.duration ?? 0.125
        guard note.beat >= 0, note.beat < 100_000, duration >= 0.01, duration < 100_000,
              (1...127).contains(note.velocity), (0...127).contains(note.releaseVelocity) else {
            return fail("out of range: beat 0 or more, duration 0.01 or more, velocity 1 to 127, releaseVelocity 0 to 127")
        }
        let start = ticks(note.beat)
        let size = ticks(duration)
        guard start + size <= length else { return fail("must end by beat \(quarters(length).formatted()), the end of the part") }
        var grace: Hit.Grace?
        if let flam = note.flam {
            guard flam.offset > 0, flam.offset <= 0.5, flam.duration >= 0.005, flam.duration <= flam.offset,
                  (1...127).contains(flam.velocity) else {
                return fail("flam needs an offset up to 0.5, a duration no longer than the offset, velocity 1 to 127")
            }
            grace = .init(offset: ticks(flam.offset), velocity: flam.velocity, length: ticks(flam.duration))
            guard start >= grace!.offset else { return fail("the flam starts before the part") }
        }
        return Hit(
            tick: start, length: size, pitch: pitch, articulation: note.articulation ?? drumMap.name(of: pitch),
            velocity: note.velocity, releaseVelocity: note.releaseVelocity, accent: note.accent, flam: grace
        )
    }
}

/// A range of bars such as `8` or `9-12`.
struct BarRange {
    let bars: ClosedRange<Int>

    init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let first = Int(parts[0]), let last = Int(parts[parts.count - 1]),
              first >= 1, first <= last else { return nil }
        bars = first...last
    }
}

/// Hits within this many ticks (1/32 quarter) before a bar line or beat count as on it.
let gridTolerance = ticksPerQuarter / 32
