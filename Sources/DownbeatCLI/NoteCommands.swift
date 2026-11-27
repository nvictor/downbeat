import ArgumentParser
import Foundation
import DownbeatKit
import MIDIKit

struct NoteCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Read and edit the notes of a region.",
        subcommands: [
            List.self, Add.self, Delete.self, Update.self, Export.self, Import.self,
            Transpose.self, Velocity.self, Quantize.self,
        ]
    )

    struct Listing: Encodable {
        struct Entry: Encodable {
            let id: Int
            let pitch: Int
            /// Logic Pro naming, with middle C (60) as C3.
            let name: String
            /// Quarter notes from the start of the region.
            let beat: Double
            let duration: Double
            let velocity: Int
            let channel: Int
        }

        let track: String
        let startBar: Int
        let endBar: Int
        let notes: [Entry]
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the notes of a region.")

        @OptionGroup var options: RegionOptions

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let listing = try withTemporaryDirectory { directory in
                let url = directory.appendingPathComponent("region.mid")
                let placement = try LogicApp().exportRegion(options.reference, to: url)
                let smf = try SMF(data: Data(contentsOf: url))
                let origin = Double(smf.bounds.start) / Double(smf.ticksPerQuarter)
                let notes = try MIDIFile(contentsOf: url).listedNotes()
                return Listing(
                    track: placement.track, startBar: placement.startBar, endBar: placement.endBar,
                    notes: notes.enumerated().map { index, note in
                        Listing.Entry(
                            id: index + 1, pitch: Int(note.pitch), name: Pitch.name(Int(note.pitch)),
                            beat: rounded(note.beat - origin), duration: rounded(note.duration),
                            velocity: Int(note.velocity), channel: note.channel
                        )
                    }
                )
            }
            if json {
                try printJSON(listing)
                return
            }
            print("id  note  beat  duration  velocity  channel")
            for note in listing.notes {
                print("\(note.id)  \(note.name)  \(note.beat)  \(note.duration)  \(note.velocity)  \(note.channel)")
            }
        }

        private func rounded(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add one note to a region, on the channel the region uses."
        )

        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption

        @Option(help: "Name or number, for example F#3 or 66. Middle C is C3.")
        var pitch: String

        @Option(help: "Start, in quarter notes from the start of the region, from 0.")
        var beat: Double

        @Option(help: "Length in quarter notes.")
        var duration: Double

        @Option(help: "1 to 127.")
        var velocity = 100

        func validate() throws {
            _ = try pitchNumber(pitch)
            try checkBeat(beat)
            try checkDuration(duration)
            try checkVelocity(velocity)
        }

        func run() throws {
            try edit(options, in: target) { file, bounds in
                try checkInside(end: bounds.start + beat + duration, of: bounds)
                try file.addNote(
                    pitch: pitchNumber(pitch), beat: bounds.start + beat, duration: duration,
                    velocity: velocity, channel: bounds.channel
                )
                return 1
            }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete one note from a region.",
            discussion: "Take the id from `downbeat note list`. Ids change after every edit."
        )

        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption

        @Option(help: "Note id from `downbeat note list`.")
        var id: Int

        func validate() throws {
            guard id >= 1 else { throw ValidationError("--id must be 1 or more.") }
        }

        func run() throws {
            try edit(options, in: target) { file, _ in
                let note = try file.deleteNote(id: id)
                print("Deleting \(Pitch.name(Int(note.pitch))), velocity \(note.velocity).")
                return 1
            }
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change one note of a region.",
            discussion: """
                Take the id from `downbeat note list`. Ids change after every edit. \
                Give at least one of --pitch, --beat, --duration and --velocity.
                """
        )

        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption

        @Option(help: "Note id from `downbeat note list`.")
        var id: Int

        @Option(help: "Name or number, for example F#3 or 66. Middle C is C3.")
        var pitch: String?

        @Option(help: "Start, in quarter notes from the start of the region, from 0.")
        var beat: Double?

        @Option(help: "Length in quarter notes.")
        var duration: Double?

        @Option(help: "1 to 127.")
        var velocity: Int?

        func validate() throws {
            guard id >= 1 else { throw ValidationError("--id must be 1 or more.") }
            guard pitch != nil || beat != nil || duration != nil || velocity != nil else {
                throw ValidationError("Give --pitch, --beat, --duration or --velocity.")
            }
            try pitch.map { _ = try pitchNumber($0) }
            try beat.map(checkBeat)
            try duration.map(checkDuration)
            try velocity.map(checkVelocity)
        }

        func run() throws {
            try edit(options, in: target) { file, bounds in
                let old = try file.note(id: id)
                // Only a moved or resized note can leave the region.
                if beat != nil || duration != nil {
                    let start = beat.map { bounds.start + $0 } ?? old.beat
                    try checkInside(end: start + (duration ?? old.duration), of: bounds)
                }
                let changed = try file.updateNote(
                    id: id, pitch: pitch.map(pitchNumber), beat: beat.map { bounds.start + $0 },
                    duration: duration, velocity: velocity
                )
                return changed ? 1 : 0
            }
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the notes of a region as JSON, for `note import`."
        )

        @OptionGroup var options: RegionOptions

        func run() throws {
            let document = try withTemporaryDirectory { directory in
                let url = directory.appendingPathComponent("region.mid")
                try LogicApp().exportRegion(options.reference, to: url)
                let smf = try SMF(data: Data(contentsOf: url))
                let origin = Double(smf.bounds.start) / Double(smf.ticksPerQuarter)
                return try MIDIFile(contentsOf: url).document(origin: origin)
            }
            try printJSON(document)
        }
    }

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Replace every note of a region with those of a JSON file.",
            discussion: """
                The file looks like the output of `note export`: \
                {"notes": [{"pitch": 60, "beat": 0, "duration": 1, "velocity": 100}]}. \
                Other events in the region stay.
                """
        )

        @Argument(help: "JSON file.")
        var input: String

        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption

        func run() throws {
            // Read the file first, so a bad one never touches Logic Pro.
            let url = URL(fileURLWithPath: input).standardizedFileURL
            guard let data = try? Data(contentsOf: url) else {
                throw ValidationError("\(url.path) cannot be read.")
            }
            let document = try NoteDocument(json: data)
            try edit(options, in: target) { file, region in
                for note in document.notes {
                    try checkInside(end: region.start + note.beat + note.duration, of: region)
                }
                let changed = try file.replaceNotes(with: document, origin: region.start, channel: region.channel)
                guard changed else { return 0 }
                print("The region now has \(document.notes.count) \(document.notes.count == 1 ? "note" : "notes").")
                return nil
            }
        }
    }

    struct Transpose: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Transpose every note.",
            discussion: "Write negative values as --semitones=-2."
        )
        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption
        @Option(help: "Semitones up or down.") var semitones: Int

        func run() throws {
            try edit(options, in: target) { file, _ in
                guard semitones != 0 else { return 0 }
                try file.transpose(semitones: semitones)
                return try file.notes().count
            }
        }
    }

    struct Velocity: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set the velocity of every note.")
        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption
        @Option(help: "1 to 127.") var value: Int

        func validate() throws {
            guard (1...127).contains(value) else { throw ValidationError("--value must be 1 to 127.") }
        }

        func run() throws {
            try edit(options, in: target) { file, _ in try file.setVelocity(value) }
        }
    }

    struct Quantize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move note starts to the grid, counted from the start of the region."
        )
        @OptionGroup var options: RegionOptions
        @OptionGroup var target: ProjectOption
        @Option(help: "Grid as a note value, for example 1/16, or 1/12 for eighth triplets.")
        var division: String

        func validate() throws {
            _ = try grid()
        }

        /// The grid in quarter notes.
        private func grid() throws -> Double {
            let parts = division.split(separator: "/")
            guard parts.count == 2, parts[0] == "1", let value = Int(parts[1]), (1...128).contains(value) else {
                throw ValidationError("--division must look like 1/16.")
            }
            return 4 / Double(value)
        }

        func run() throws {
            try edit(options, in: target) { file, bounds in
                try file.quantize(grid: grid(), origin: bounds.start, end: bounds.end)
            }
        }
    }
}

/// A region in quarter notes from the beginning of its exported file.
private struct Span {
    let start: Double
    let end: Double
    /// The channel its events use, or 1 when it has none.
    let channel: Int
}

/// Exports a region, applies `change` and puts the result back.
/// `change` returns the number of notes changed, or nil when it reports the result itself.
private func edit(
    _ options: RegionOptions,
    in target: ProjectOption,
    _ change: (MIDIFile, Span) throws -> Int?
) throws {
    let app = try target.app()
    try withTemporaryDirectory { directory in
        let exported = directory.appendingPathComponent("region.mid")
        let edited = directory.appendingPathComponent("edited.mid")
        let placement = try app.exportRegion(options.reference, to: exported)
        let smf = try SMF(data: Data(contentsOf: exported))
        let ticks = Double(smf.ticksPerQuarter)
        let file = try MIDIFile(contentsOf: exported)
        let count = try change(file, Span(
            start: Double(smf.bounds.start) / ticks, end: Double(smf.bounds.end) / ticks,
            channel: smf.channels.min() ?? 1
        ))
        guard count != 0 else {
            print("No notes needed changing.")
            return
        }
        try file.save(to: edited)
        try MIDIFile.keepBounds(of: edited, start: smf.bounds.start, end: smf.bounds.end)
        try app.importRegion(edited, at: placement)
        if let count { print("Changed \(count) \(count == 1 ? "note" : "notes").") }
    }
}

private func pitchNumber(_ text: String) throws -> Int {
    guard let number = Pitch.parse(text) else {
        throw ValidationError("--pitch must be 0 to 127, or a name such as F#3.")
    }
    return number
}

private func checkBeat(_ beat: Double) throws {
    guard beat >= 0, beat.isFinite else { throw ValidationError("--beat must be 0 or more.") }
}

private func checkDuration(_ duration: Double) throws {
    guard duration >= 0.01, duration.isFinite else { throw ValidationError("--duration must be 0.01 or more.") }
}

private func checkVelocity(_ velocity: Int) throws {
    guard (1...127).contains(velocity) else { throw ValidationError("--velocity must be 1 to 127.") }
}

/// `end` and `bounds` are in quarter notes from the beginning of the file.
private func checkInside(end: Double, of bounds: Span) throws {
    guard end <= bounds.end + 1e-6 else {
        let length = (bounds.end - bounds.start).formatted()
        throw DownbeatError("The note must end by beat \(length), the end of the region.")
    }
}
