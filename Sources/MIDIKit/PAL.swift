import Foundation

/// Parts Arrangement Language 1.0.0: parts, repeats and metadata.
public struct PAL: Equatable, Sendable {
    public struct Part: Equatable, Sendable {
        /// The letter with its variation marks, such as `B'`.
        public let id: String
        public let bars: Int
    }

    /// The parts in playing order, with repeats and groups expanded.
    public let parts: [Part]
    public let meter: Meter?
    public let tempo: Double?

    public init(_ text: String) throws {
        func fail(_ message: String) -> LayoutError { LayoutError(description: message) }
        var fields = text.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let expression = fields.popLast() else { throw fail("no parts") }
        var meter: Meter?
        var tempo: Double?
        for field in fields {
            if let signature = Meter(field) {
                meter = signature
            } else if let match = field.wholeMatch(of: /(\d+(?:\.\d+)?) bpm/), let value = Double(match.1) {
                tempo = value
            } else {
                throw fail("unknown metadata \"\(field)\"")
            }
        }

        func part(_ token: Substring) throws -> [Part] {
            guard let match = token.wholeMatch(of: /([A-Z]'*)([1-9]\d{0,3})(?:x(\d{1,3}))?/),
                  let bars = Int(match.2) else { throw fail("unknown part \"\(token)\"") }
            let count = match.3.flatMap { Int($0) } ?? 1
            if match.3 != nil && count < 2 { throw fail("a repeat count is 2 or more: \"\(token)\"") }
            return Array(repeating: Part(id: String(match.1), bars: bars), count: count)
        }

        var parts: [Part] = []
        for item in expression.matches(of: /\([^()]*\)\S*|\S+/).map(\.output) {
            guard item.hasPrefix("(") else {
                parts += try part(item)
                continue
            }
            guard let match = item.wholeMatch(of: /\(([^()]*)\)x(\d{1,3})/), let count = Int(match.2), count >= 2 else {
                throw fail("a group needs a repeat count of 2 or more: \"\(item)\"")
            }
            let inside = match.1.split(whereSeparator: \.isWhitespace)
            guard inside.count >= 2 else { throw fail("a group needs two parts or more: \"\(item)\"") }
            let block = try inside.flatMap(part)
            for _ in 0..<count { parts += block }
        }
        guard !parts.isEmpty else { throw fail("no parts") }
        var lengths: [String: Int] = [:]
        for part in parts where lengths.updateValue(part.bars, forKey: part.id).map({ $0 != part.bars }) == true {
            throw fail("part \(part.id) has two different lengths")
        }
        self.parts = parts
        self.meter = meter
        self.tempo = tempo
    }

    /// Each part once, in order of first appearance.
    public var distinct: [Part] {
        var seen: Set<String> = []
        return parts.filter { seen.insert($0.id).inserted }
    }
}
