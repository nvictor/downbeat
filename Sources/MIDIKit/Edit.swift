import Foundation

/// A batch of changes to one or more drum voices of an arrangement.
public struct EditBatch: Sendable {
    public struct Operation: Sendable {
        public enum Kind: String, Sendable { case replace, copy, remove }

        public var op: Kind
        public var section: String
        /// A clip name, such as `16 fill b`.
        public var part: String?
        /// Section bars, such as `8` or `9-10`.
        public var bars: String?
        /// A half-open range of bar positions: `[4, 5]` is all of beat 4.
        public var beats: [Double]?
        public var articulations: [String]
        /// The new articulation of `replace`.
        public var with: String?
        /// With `replace`: write a straight line, one hit every so many quarter notes.
        public var every: Double?
        /// Velocities cycled along that line.
        public var velocity: [Int]?
        /// The destination of `copy`.
        public var to: (section: String, bar: Int)?
        /// What to do when parts sharing one source would end up different.
        public var shared: Shared?
    }

    public enum Shared: String, Sendable { case source, detach }

    public var operations: [Operation]

    public init(json: Data) throws {
        var reader = try JSONReader(JSONReader.parse(json), "the batch")
        let values = try reader.required(reader.array("operations"), "operations")
        try reader.finish()
        operations = try values.enumerated().map { index, value in
            var reader = try JSONReader(value, "operation \(index + 1)")
            let name = try reader.required(reader.string("op"), "op")
            guard let op = Operation.Kind(rawValue: name) else { throw reader.fail("\"op\" is replace, copy or remove") }
            var operation = Operation(
                op: op,
                section: try reader.required(reader.string("section"), "section"),
                articulations: try reader.required(
                    reader.oneOrMany("articulations", "a name") { $0 as? String }, "articulations")
            )
            operation.part = try reader.string("part")
            if let value = reader.raw("bars") {
                guard let text = value as? String ?? JSONReader.integer(value).map(String.init) else {
                    throw reader.fail("\"bars\" looks like \"8\" or \"9-10\"")
                }
                operation.bars = text
            }
            if let list = try reader.array("beats") {
                let beats = list.compactMap(JSONReader.number)
                guard list.count == 2, beats.count == 2, beats[0] >= 1, beats[1] > beats[0] else {
                    throw reader.fail("\"beats\" looks like [4, 5]")
                }
                operation.beats = beats
            }
            if op == .replace {
                operation.with = try reader.required(reader.string("with"), "with")
                operation.every = try reader.double("every")
                operation.velocity = try reader.oneOrMany("velocity", "a whole number", JSONReader.integer)
                if let every = operation.every, !(0.0625...64).contains(every) {
                    throw reader.fail("\"every\" must be 0.0625 or more")
                }
                if operation.velocity != nil && operation.every == nil {
                    throw reader.fail("\"velocity\" needs \"every\"")
                }
                if operation.velocity?.contains(where: { !(1...127).contains($0) }) == true {
                    throw reader.fail("velocity must be 1 to 127")
                }
            }
            if op == .copy {
                var target = try JSONReader(reader.required(reader.raw("to"), "to"), "operation \(index + 1), to")
                operation.to = (
                    try target.required(target.string("section"), "section"),
                    try target.required(target.int("bar"), "bar")
                )
                try target.finish()
            }
            if let text = try reader.string("shared") {
                guard let shared = Shared(rawValue: text) else { throw reader.fail("\"shared\" is source or detach") }
                operation.shared = shared
            }
            try reader.finish()
            return operation
        }
    }
}

public struct EditReport: Encodable, Equatable, Sendable {
    public struct Part: Encodable, Equatable, Sendable {
        public let section: String
        public let clip: String
        /// Notes the operation selected.
        public let matched: Int
        public let removed: Int
        public let added: Int
        public let changed: Int
        /// `edited`, `detached` (got its own notes) or `shared` (follows its changed source).
        public let action: String
        /// GUS voices written out as notes.
        public let voicesWrittenOut: Int
    }

    public struct Operation: Encodable, Equatable, Sendable {
        public let op: String
        public let parts: [Part]
    }

    /// False when the batch leaves the arrangement as it was.
    public var changed: Bool
    public var operations: [Operation]
}

private struct Content: Equatable {
    var voices: [Arrangement.Voice]
    var notes: [Arrangement.Note]
}

private struct Place: Hashable {
    let section: Int
    let part: Int
}

private struct Outcome {
    var content: Content
    var matched = 0
    var voicesWrittenOut = 0
}

extension Arrangement {
    /// Applies every operation to a copy. Throws without a result when any of them fails.
    public func applying(_ batch: EditBatch) throws -> (arrangement: Arrangement, report: EditReport) {
        _ = try resolve(humanized: false)
        var result = self
        var report = EditReport(changed: false, operations: [])
        for (index, operation) in batch.operations.enumerated() {
            do {
                report.operations.append(.init(op: operation.op.rawValue, parts: try result.apply(operation)))
                _ = try result.resolve(humanized: false)
            } catch {
                throw LayoutError(description: "operation \(index + 1) (\(operation.op.rawValue)): \(error)")
            }
        }
        report.changed = result != self
        return (result, report)
    }

    private func sectionIndex(_ name: String) throws -> Int {
        guard let index = sections.firstIndex(where: { $0.name == name }) else {
            throw LayoutError(description: "no section \"\(name)\"")
        }
        return index
    }

    private func meter(of section: Int) -> Meter {
        (sections[section].meter ?? meter).flatMap(Meter.init) ?? (try? pal.map(PAL.init))?.meter ?? .common
    }

    private func part(_ place: Place) -> Part { sections[place.section].parts[place.part] }

    private func owner(_ place: Place) -> Place {
        guard let use = part(place).use, let found = find(use, from: place.section),
              let index = sections[found.section].parts.firstIndex(of: found.part) else { return place }
        return Place(section: found.section, part: index)
    }

    private func content(_ place: Place) -> Content {
        let source = part(owner(place))
        return Content(voices: source.voices, notes: source.notes)
    }

    /// The notes a voice plays in a part.
    private func notes(of voice: Voice, at place: Place) throws -> [Note] {
        let meter = meter(of: place.section)
        let lines = try voice.gus.map { try GUS($0, meter: meter) }
        return notes(of: voice, lines: lines, bars: part(place).bars, meter: meter).map(\.note)
    }

    private func allNotes(_ content: Content, at place: Place) throws -> [Note] {
        try content.voices.flatMap { try notes(of: $0, at: place) } + content.notes
    }

    private func articulation(_ note: Note) -> String? {
        note.articulation ?? note.pitch.flatMap(drumMap.name(of:))
    }

    private func pitch(_ note: Note) -> Int {
        note.pitch ?? note.articulation.flatMap { drumMap.articulations[$0] } ?? -1
    }

    private func ordered(_ notes: [Note]) -> [Note] {
        notes.sorted {
            (ticks($0.beat), pitch($0), $0.velocity) < (ticks($1.beat), pitch($1), $1.velocity)
        }
    }

    private mutating func apply(_ operation: EditBatch.Operation) throws -> [EditReport.Part] {
        let selected = try drumMap.expand(operation.articulations)
        let from = try sectionIndex(operation.section)
        let length = try resolve(humanized: false).sections.first { $0.name == operation.section }!.bars
        if let name = operation.part, !sections[from].parts.contains(where: { $0.clip == name }) {
            throw LayoutError(description: "no part \"\(name)\" in \(operation.section)")
        }
        var range = 1...length
        if let text = operation.bars {
            guard let parsed = BarRange(text)?.bars, parsed.upperBound <= length else {
                throw LayoutError(description: "bars \"\(text)\" are not within 1 to \(length)")
            }
            range = parsed
        } else if let name = operation.part, let part = sections[from].parts.first(where: { $0.clip == name }) {
            range = part.bar...(part.bar + part.bars - 1)
        }

        /// The section bar and bar position of a note in a part.
        func position(_ note: Note, _ place: Place) -> (bar: Int, tick: Int) {
            let meter = meter(of: place.section)
            let tick = ticks(note.beat)
            let bar = (tick + gridTolerance) / meter.barTicks
            return (part(place).bar + bar, tick - bar * meter.barTicks)
        }
        func inBeats(_ tick: Int, _ section: Int) -> Bool {
            guard let beats = operation.beats else { return true }
            let size = Double(meter(of: section).beatTicks)
            let low = (beats[0] - 1) * size - Double(gridTolerance)
            let high = (beats[1] - 1) * size - Double(gridTolerance)
            return Double(tick) >= low && Double(tick) < high
        }
        func matches(_ note: Note, _ place: Place, _ bars: ClosedRange<Int>) -> Bool {
            guard let name = articulation(note), selected.contains(name) else { return false }
            let at = position(note, place)
            return bars.contains(at.bar) && inBeats(at.tick, place.section)
        }
        func overlaps(_ place: Place, _ bars: ClosedRange<Int>) -> Bool {
            let part = part(place)
            return bars.overlaps(part.bar...(part.bar + part.bars - 1))
        }
        let places = sections.indices.flatMap { section in
            sections[section].parts.indices.map { Place(section: section, part: $0) }
        }
        func inSource(_ place: Place) -> Bool {
            place.section == from && (operation.part == nil || part(place).clip == operation.part)
                && overlaps(place, range)
        }

        // Where the operation writes.
        var target = from
        var targetRange = range
        var pasted: [(bar: Int, tick: Int, note: Note)] = []
        if operation.op == .copy, let to = operation.to {
            target = try sectionIndex(to.section)
            guard meter(of: target) == meter(of: from) else {
                throw LayoutError(description: "the two sections have different meters")
            }
            let size = try resolve(humanized: false).sections.first { $0.name == to.section }!.bars
            guard to.bar >= 1, to.bar + range.count - 1 <= size else {
                throw LayoutError(description: "the destination is not within bars 1 to \(size)")
            }
            targetRange = to.bar...(to.bar + range.count - 1)
            for place in places where inSource(place) {
                for note in try allNotes(content(place), at: place) where matches(note, place, range) {
                    let at = position(note, place)
                    pasted.append((at.bar - range.lowerBound + to.bar, at.tick, note))
                }
            }
            for item in pasted where !places.contains(where: { $0.section == target && overlaps($0, item.bar...item.bar) }) {
                throw LayoutError(description: "no part covers bar \(item.bar) of \(to.section)")
            }
        }
        func inScope(_ place: Place) -> Bool {
            operation.op == .copy ? place.section == target && overlaps(place, targetRange) : inSource(place)
        }

        func transform(_ place: Place) throws -> Outcome {
            let old = content(place)
            var new = old
            var written = 0
            new.voices = []
            for voice in old.voices {
                let notes = try notes(of: voice, at: place)
                let touched = notes.contains { matches($0, place, targetRange) }
                    || (operation.every != nil && notes.contains { note in
                        let at = position(note, place)
                        return articulation(note) == operation.with && targetRange.contains(at.bar)
                            && inBeats(at.tick, place.section)
                    })
                if touched {
                    new.notes += notes
                    written += 1
                } else {
                    new.voices.append(voice)
                }
            }
            let matched = new.notes.filter { matches($0, place, targetRange) }.count
            switch operation.op {
            case .remove:
                new.notes.removeAll { matches($0, place, targetRange) }
            case .copy:
                new.notes.removeAll { matches($0, place, targetRange) }
                let meter = meter(of: place.section)
                let part = part(place)
                for item in pasted where (part.bar..<part.bar + part.bars).contains(item.bar) {
                    var note = item.note
                    note.beat = quarters((item.bar - part.bar) * meter.barTicks + item.tick)
                    new.notes.append(note)
                }
            case .replace:
                guard let with = operation.with, drumMap.articulations[with] != nil else {
                    throw LayoutError(description: "unknown articulation \"\(operation.with ?? "")\"")
                }
                if let every = operation.every {
                    func replaced(_ note: Note) -> Bool {
                        if matches(note, place, targetRange) { return true }
                        let at = position(note, place)
                        return articulation(note) == with && targetRange.contains(at.bar) && inBeats(at.tick, place.section)
                    }
                    // Only bars that played one of the two get the line, so silent bars stay silent.
                    let bars = Set(new.notes.filter(replaced).map { position($0, place).bar })
                    new.notes.removeAll(where: replaced)
                    let meter = meter(of: place.section)
                    for bar in bars.sorted() {
                        var step = 0
                        while ticks(Double(step) * every) < meter.barTicks {
                            let tick = ticks(Double(step) * every)
                            if inBeats(tick, place.section) {
                                let velocities = operation.velocity ?? [100]
                                new.notes.append(Note(
                                    articulation: with,
                                    beat: quarters((bar - part(place).bar) * meter.barTicks + tick),
                                    velocity: velocities[step % velocities.count]
                                ))
                            }
                            step += 1
                        }
                    }
                } else {
                    var taken = Set(new.notes.filter { !matches($0, place, targetRange) && articulation($0) == with }
                        .map { ticks($0.beat) })
                    new.notes = new.notes.compactMap { note in
                        guard matches(note, place, targetRange) else { return note }
                        guard taken.insert(ticks(note.beat)).inserted else { return nil }
                        var swapped = note
                        swapped.articulation = with
                        swapped.pitch = nil
                        return swapped
                    }
                }
            }
            // Keep the part as written when it would sound the same.
            if try ordered(allNotes(new, at: place)) == ordered(allNotes(old, at: place)) {
                return Outcome(content: old, matched: matched)
            }
            new.notes = ordered(new.notes)
            return Outcome(content: new, matched: matched, voicesWrittenOut: written)
        }

        var outcomes: [Place: Outcome] = [:]
        for place in places where inScope(place) { outcomes[place] = try transform(place) }

        // Decide, for each source, who keeps sharing it.
        let original = self
        var contents: [Place: Content] = [:]
        var uses: [Place: Place] = [:]
        var actions: [Place: String] = [:]
        var handled: Set<Place> = []
        for place in places where outcomes[place] != nil {
            let source = original.owner(place)
            guard handled.insert(source).inserted else { continue }
            let members = places.filter { original.owner($0) == source }
            let old = original.content(source)
            func after(_ member: Place) -> Content { outcomes[member]?.content ?? old }
            if members.allSatisfy({ after($0) == old }) { continue }
            if members.allSatisfy({ after($0) == after(members[0]) }) {
                contents[source] = after(members[0])
                for member in members { actions[member] = "edited" }
                continue
            }
            let names = members.map { "\(sections[$0.section].name) / \(part($0).clip)" }
            let outside = members.filter { outcomes[$0] == nil }
                .map { "\(sections[$0.section].name) / \(part($0).clip)" }
            switch operation.shared {
            case nil:
                let scope = outside.isEmpty ? "" : " Out of scope: \(outside.joined(separator: ", "))."
                throw LayoutError(description: """
                    \(names.joined(separator: ", ")) share one source and would end up different.\(scope) \
                    Set "shared" to "source" to change them all, or "detach" to give changed parts their own notes.
                    """)
            case .source:
                let wanted = Set(members.compactMap { outcomes[$0] != nil ? $0 : nil })
                let first = members.first { wanted.contains($0) }!
                guard wanted.allSatisfy({ after($0) == after(first) }) else {
                    throw LayoutError(description: "\(names.joined(separator: ", ")) would need different notes. Use \"detach\".")
                }
                contents[source] = after(first)
                for member in members { actions[member] = wanted.contains(member) ? "edited" : "shared" }
            case .detach:
                var groups: [(content: Content, members: [Place])] = []
                for member in members {
                    if let index = groups.firstIndex(where: { $0.content == after(member) }) {
                        groups[index].members.append(member)
                    } else {
                        groups.append((after(member), [member]))
                    }
                }
                for group in groups {
                    // The source stays where it is if its group has it. Otherwise the first member owns the notes.
                    let head = group.members.contains(source) ? source : group.members[0]
                    let changed = group.content != old
                    if head == source {
                        if changed {
                            contents[source] = group.content
                            for member in group.members { actions[member] = "edited" }
                        }
                        continue
                    }
                    contents[head] = group.content
                    for member in group.members {
                        if member != head { uses[member] = head }
                        if changed { actions[member] = "detached" }
                    }
                }
            }
        }

        let reports: [EditReport.Part] = try places.compactMap { place in
            let outcome = outcomes[place]
            guard actions[place] != nil || (outcome?.matched ?? 0) > 0 else { return nil }
            let old = try allNotes(original.content(place), at: place)
            var newContent = original.content(place)
            if actions[place] != nil {
                let head = uses[place] ?? (contents[place] != nil ? place : original.owner(place))
                newContent = contents[head] ?? newContent
            }
            let new = try allNotes(newContent, at: place)
            func keyed(_ notes: [Note]) -> [[Int]: [Note]] {
                Dictionary(grouping: ordered(notes)) { [ticks($0.beat), pitch($0)] }
            }
            let before = keyed(old), later = keyed(new)
            return EditReport.Part(
                section: sections[place.section].name, clip: part(place).clip, matched: outcome?.matched ?? 0,
                removed: before.keys.filter { later[$0] == nil }.reduce(0) { $0 + before[$1]!.count },
                added: later.keys.filter { before[$0] == nil }.reduce(0) { $0 + later[$1]!.count },
                changed: before.keys.filter { key in
                    guard let other = later[key] else { return false }
                    return other.map { [$0.velocity, $0.releaseVelocity] } != before[key]!.map { [$0.velocity, $0.releaseVelocity] }
                }.count,
                action: actions[place] ?? "unchanged", voicesWrittenOut: outcome?.voicesWrittenOut ?? 0
            )
        }

        // Write the new contents first, then point the detached parts at their new sources.
        for (place, content) in contents {
            sections[place.section].parts[place.part].use = nil
            sections[place.section].parts[place.part].voices = content.voices
            sections[place.section].parts[place.part].notes = content.notes
        }
        for (place, head) in uses {
            let clip = part(head).clip
            sections[place.section].parts[place.part].use =
                head.section == place.section ? clip : "\(sections[head.section].name)/\(clip)"
            sections[place.section].parts[place.part].voices = []
            sections[place.section].parts[place.part].notes = []
        }
        return reports
    }
}
