import Foundation

/// The notes of a region as JSON, written by `note export` and read by `note import`.
public struct NoteDocument: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// 0 to 127.
        public var pitch: Int
        /// Start in quarter notes from the start of the region.
        public var beat: Double
        /// Length in quarter notes.
        public var duration: Double
        public var velocity: Int
        public var releaseVelocity: Int

        public init(pitch: Int, beat: Double, duration: Double, velocity: Int = 100, releaseVelocity: Int = 64) {
            self.pitch = pitch
            self.beat = beat
            self.duration = duration
            self.velocity = velocity
            self.releaseVelocity = releaseVelocity
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                pitch: try values.decode(Int.self, forKey: .pitch),
                beat: try values.decode(Double.self, forKey: .beat),
                duration: try values.decode(Double.self, forKey: .duration),
                velocity: try values.decodeIfPresent(Int.self, forKey: .velocity) ?? 100,
                releaseVelocity: try values.decodeIfPresent(Int.self, forKey: .releaseVelocity) ?? 64
            )
        }

        fileprivate func isSame(as other: Entry) -> Bool {
            pitch == other.pitch && velocity == other.velocity && releaseVelocity == other.releaseVelocity
                && abs(beat - other.beat) < 1e-5 && abs(duration - other.duration) < 1e-5
        }

        fileprivate var order: (Double, Int, Double, Int, Int) {
            (beat, pitch, duration, velocity, releaseVelocity)
        }
    }

    public var notes: [Entry]

    public init(notes: [Entry]) {
        self.notes = notes
    }

    /// Reads a document and checks every value that does not depend on the region.
    public init(json: Data) throws {
        do {
            self = try JSONDecoder().decode(Self.self, from: json)
        } catch let DecodingError.keyNotFound(key, context) {
            throw LayoutError(description: "\(Self.place(context.codingPath)) has no \"\(key.stringValue)\"")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw LayoutError(description: "\(Self.place(context.codingPath)) has a value of the wrong type")
        } catch {
            throw LayoutError(description: "the file is not valid JSON")
        }
        for (index, note) in notes.enumerated() {
            guard (0...127).contains(note.pitch), note.beat >= 0, note.duration >= 0.01,
                  (1...127).contains(note.velocity), (0...127).contains(note.releaseVelocity) else {
                throw LayoutError(description: """
                    note \(index + 1) is out of range: pitch 0 to 127, beat 0 or more, duration 0.01 or more, \
                    velocity 1 to 127, releaseVelocity 0 to 127
                    """)
            }
        }
    }

    private static func place(_ path: [CodingKey]) -> String {
        path.compactMap(\.intValue).first.map { "note \($0 + 1)" } ?? "the document"
    }
}

extension MIDIFile {
    /// The notes in listing order, with beats counted from `origin`.
    public func document(origin: Double) throws -> NoteDocument {
        func rounded(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }
        return NoteDocument(notes: try listedNotes().map {
            .init(
                pitch: Int($0.pitch), beat: rounded($0.beat - origin), duration: rounded($0.duration),
                velocity: Int($0.velocity), releaseVelocity: Int($0.releaseVelocity)
            )
        })
    }

    /// Replaces every note with those of `document`, keeping the other events.
    /// Returns false when nothing differs. After a throw the file is incomplete, so discard it.
    public func replaceNotes(with document: NoteDocument, origin: Double, channel: Int) throws -> Bool {
        let old = try self.document(origin: origin).notes.sorted { $0.order < $1.order }
        let new = document.notes.sorted { $0.order < $1.order }
        if old.count == new.count && zip(old, new).allSatisfy({ $0.isSame(as: $1) }) { return false }
        while try !notes().isEmpty { try deleteNote(id: 1) }
        for note in new {
            try addNote(
                pitch: note.pitch, beat: origin + note.beat, duration: note.duration,
                velocity: note.velocity, channel: channel, releaseVelocity: UInt8(note.releaseVelocity)
            )
        }
        return true
    }
}
