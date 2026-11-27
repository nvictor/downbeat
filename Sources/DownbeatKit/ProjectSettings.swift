/// Musical settings of a project, checked and spelled the way Logic Pro's menus spell them.
public enum ProjectSettings {
    public static let tempoRange = 5...990
    public static let signatures = ["3/4", "4/4", "5/4", "6/8", "7/8", "12/8"]

    private static let majorKeys = ["C♯", "F♯", "B", "E", "A", "D", "G", "C", "F", "B♭", "E♭", "A♭", "D♭", "G♭", "C♭"]
    private static let minorKeys = ["A♯", "D♯", "G♯", "C♯", "F♯", "B", "E", "A", "D", "G", "C", "F", "B♭", "E♭", "A♭"]

    public static func checkTempo(_ tempo: Int) throws {
        guard tempoRange.contains(tempo) else {
            throw DownbeatError("Tempo must be \(tempoRange.lowerBound) to \(tempoRange.upperBound).")
        }
    }

    public static func checkSignature(_ signature: String) throws {
        guard signatures.contains(signature) else {
            throw DownbeatError("The time signature must be one of \(signatures.joined(separator: ", ")).")
        }
    }

    /// Turns input such as `f# minor` or `Bb major` into the menu title, such as `F♯ Minor`.
    public static func keyTitle(_ key: String) throws -> String {
        let words = key.split(separator: " ").map(String.init)
        if words.count == 2, let first = words[0].first {
            let accidental = words[0].dropFirst()
                .replacingOccurrences(of: "#", with: "♯")
                .replacingOccurrences(of: "b", with: "♭")
            let note = first.uppercased() + accidental
            switch words[1].lowercased() {
            case "major" where majorKeys.contains(note): return "\(note) Major"
            case "minor" where minorKeys.contains(note): return "\(note) Minor"
            default: break
            }
        }
        throw DownbeatError("Write the key like \"A minor\", \"F# minor\" or \"Bb major\".")
    }
}
