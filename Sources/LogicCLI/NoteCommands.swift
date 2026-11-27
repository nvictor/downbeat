import ArgumentParser
import Foundation
import LogicKit
import MIDIKit

struct NoteCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Read and edit the notes of a region.",
        subcommands: [List.self, Transpose.self, Velocity.self, Quantize.self]
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
                let notes = try MIDIFile(contentsOf: url).notes()
                    .sorted { ($0.beat, $0.pitch) < ($1.beat, $1.pitch) }
                return Listing(
                    track: placement.track, startBar: placement.startBar, endBar: placement.endBar,
                    notes: notes.enumerated().map { index, note in
                        Listing.Entry(
                            id: index + 1, pitch: Int(note.pitch), name: pitchName(Int(note.pitch)),
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

/// Exports a region, applies `change` and puts the result back.
/// `change` gets the region bounds in quarter notes and returns the number of notes changed.
private func edit(
    _ options: RegionOptions,
    in target: ProjectOption,
    _ change: (MIDIFile, (start: Double, end: Double)) throws -> Int
) throws {
    let app = try target.app()
    try withTemporaryDirectory { directory in
        let exported = directory.appendingPathComponent("region.mid")
        let edited = directory.appendingPathComponent("edited.mid")
        let placement = try app.exportRegion(options.reference, to: exported)
        let smf = try SMF(data: Data(contentsOf: exported))
        let ticks = Double(smf.ticksPerQuarter)
        let file = try MIDIFile(contentsOf: exported)
        let count = try change(file, (Double(smf.bounds.start) / ticks, Double(smf.bounds.end) / ticks))
        guard count > 0 else {
            print("No notes needed changing.")
            return
        }
        try file.save(to: edited)
        try app.importRegion(edited, at: placement)
        print("Changed \(count) notes.")
    }
}

private func pitchName(_ pitch: Int) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "\(names[pitch % 12])\(pitch / 12 - 2)"
}
