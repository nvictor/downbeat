import Foundation

/// A block of an EZdrummer project, which is plain text: `Name {`, `Key values` and `}`.
struct Node {
    var header: [String]
    var entries: [(key: String, values: [String])] = []
    var children: [Node] = []

    var name: String { header.joined(separator: " ") }

    func values(_ key: String) -> [String]? { entries.first { $0.key == key }?.values }
    func string(_ key: String) -> String? { values(key)?.first }
    func number(_ key: String) -> Double? { string(key).flatMap(Double.init) }
    func flag(_ key: String) -> Bool? { number(key).map { $0 != 0 } }
    func child(_ name: String) -> Node? { children.first { $0.header.first == name } }
    func all(_ name: String) -> [Node] { children.filter { $0.header.first == name } }

    static func parse(_ text: String) throws -> Node {
        var stack = [Node(header: [])]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "}" {
                guard stack.count > 1 else { throw ProjectError("a block closes that was never opened") }
                let node = stack.removeLast()
                stack[stack.count - 1].children.append(node)
            } else if trimmed.hasSuffix("{") {
                stack.append(Node(header: tokens(trimmed.dropLast())))
            } else {
                var words = tokens(trimmed[...])
                guard !words.isEmpty else { continue }
                let key = words.removeFirst()
                stack[stack.count - 1].entries.append((key, words))
            }
        }
        guard stack.count == 1 else { throw ProjectError("a block is not closed. The file may be cut off") }
        return stack[0]
    }

    /// Words separated by spaces. A quoted string stays whole, without its quotes.
    private static func tokens(_ line: Substring) -> [String] {
        var result: [String] = []
        var word = ""
        var quoted = false
        var started = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
                started = true
            } else if character == " " && !quoted {
                if started { result.append(word) }
                word = ""
                started = false
            } else {
                word.append(character)
                started = true
            }
        }
        if started { result.append(word) }
        return result
    }
}

public struct ProjectError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}
