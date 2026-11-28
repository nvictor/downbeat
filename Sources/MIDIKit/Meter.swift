/// A time signature, and the conversions between bars and quarter notes.
public struct Meter: Equatable, Sendable, CustomStringConvertible {
    public let numerator: Int
    public let denominator: Int

    public static let common = Meter(numerator: 4, denominator: 4)

    init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    /// Reads `4/4`, `6/8` and so on.
    public init?(_ text: String) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let numerator = Int(parts[0]), let denominator = Int(parts[1]),
              (1...32).contains(numerator), [1, 2, 4, 8, 16, 32].contains(denominator) else { return nil }
        self.init(numerator: numerator, denominator: denominator)
    }

    public var description: String { "\(numerator)/\(denominator)" }

    /// Length of one beat in quarter notes.
    public var quartersPerBeat: Double { 4 / Double(denominator) }

    /// Length of one bar in quarter notes.
    public var barQuarters: Double { Double(numerator) * quartersPerBeat }
}
