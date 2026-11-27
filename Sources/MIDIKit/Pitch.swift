/// Note names as Logic Pro shows them, with middle C (60) as C3.
public enum Pitch {
    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func name(_ pitch: Int) -> String {
        "\(names[pitch % 12])\(pitch / 12 - 2)"
    }

    /// Reads a number (0 to 127) or a name such as `C3`, `F#2` or `Bb-1`.
    public static func parse(_ text: String) -> Int? {
        if let number = Int(text) { return (0...127).contains(number) ? number : nil }
        guard let match = text.wholeMatch(of: /([A-Ga-g])([#b]?)(-?\d)/),
              let natural = names.firstIndex(of: match.1.uppercased()),
              let octave = Int(match.3) else { return nil }
        let shift = match.2 == "#" ? 1 : match.2 == "b" ? -1 : 0
        let pitch = (octave + 2) * 12 + natural + shift
        return (0...127).contains(pitch) ? pitch : nil
    }
}
