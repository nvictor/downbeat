import Foundation

/// Groove Unified Syntax 1.3.0: an expression read as the sixteenth steps of one bar.
/// GUS is lossy, so each expression has one canonical reading, the same as in the Atalanta
/// diary: a neighbor hit is the sixteenth right before (`<`) or after (`>`) its pulse,
/// wrapping around the bar.
public struct GUS: Equatable, Sendable {
    public let meter: Meter
    /// One entry per sixteenth of the bar. True where there is a hit.
    public let steps: [Bool]

    private static let sizes = ["2/4": 8, "3/4": 12, "4/4": 16, "2/2": 16, "5/4": 20, "6/8": 12]
    private static let defaults = [2: "2/4", 3: "3/4", 4: "4/4", 5: "5/4", 6: "3/4", 8: "4/4", 10: "5/4", 16: "4/4"]

    /// `meter` is the meter of the surrounding bar. A signature in the text must match it.
    public init(_ text: String, meter: Meter? = nil) throws {
        func fail(_ message: String) -> LayoutError { LayoutError(description: message) }
        var fields = text.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let expression = fields.popLast(), fields.count <= 1 else { throw fail("cannot read \"\(text)\"") }
        var tokens = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty, let head = tokens.first, head.hasPrefix("P"),
              let pulses = Int(head.dropFirst()), let usual = Self.defaults[pulses] else {
            throw fail("unknown pulse in \"\(text)\"")
        }
        tokens.removeFirst()
        if let given = fields.first, let meter, given != meter.description {
            throw fail("\(given) does not match the \(meter) bar")
        }
        let signature = fields.first ?? meter?.description ?? usual
        guard let count = Self.sizes[signature], count % pulses == 0, let parsed = Meter(signature) else {
            throw fail("\(head) does not fit \(signature)")
        }
        let width = count / pulses

        var present = Set(1...pulses)
        var extra: Set<Int> = []
        var used: Set<Int> = []
        for token in tokens {
            if ["A↓", "A↑", "A↔"].contains(token) { continue } // anchor: felt gravity, no hits
            guard let match = token.wholeMatch(of: /([OSNU])\((\d+(?:,\d+)*)\)(<>|<|>)?/) else {
                throw fail("unknown token \"\(token)\"")
            }
            let kind = String(match.1)
            let timing = match.3.map(String.init) ?? ""
            if (kind == "S" || kind == "N") && timing.isEmpty { throw fail("\(token) needs <, > or <>") }
            if (kind == "O" || kind == "U") && !timing.isEmpty { throw fail("\(token) cannot take \(timing)") }
            if kind == "U" && width != 4 { throw fail("U is only valid with quarter pulses") }
            if !timing.isEmpty && width == 1 { throw fail("\(token): no neighbor steps in P16") }
            for item in match.2.split(separator: ",") {
                guard let pulse = Int(item), (1...pulses).contains(pulse) else {
                    throw fail("\(token): pulse \(item) is out of range")
                }
                let start = (pulse - 1) * width
                if kind == "U" {
                    extra.insert(start + 2)
                    continue
                }
                guard used.insert(pulse).inserted else { throw fail("pulse \(pulse) has more than one of O, S, N") }
                if kind != "N" { present.remove(pulse) }
                if timing.contains("<") { extra.insert((start - 1 + count) % count) }
                if timing.contains(">") { extra.insert(start + 1) }
            }
        }
        let hits = extra.union(present.map { ($0 - 1) * width })
        self.meter = parsed
        steps = (0..<count).map(hits.contains)
    }

    /// The sixteenth steps that are hit, counted from 1.
    public var hits: [Int] { steps.indices.filter { steps[$0] }.map { $0 + 1 } }
}
