import Foundation

/// A JSON value whose objects keep their key order, so a rewritten arrangement stays readable.
indirect enum JSONValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([(String, JSONValue)])

    /// Builds an object, leaving out the missing values.
    static func fields(_ pairs: [(String, JSONValue?)]) -> JSONValue {
        .object(pairs.compactMap { key, value in value.map { (key, $0) } })
    }

    /// Pretty text. A value that fits stays on one line.
    func text(indent: Int = 0, width: Int = 110) -> String {
        let line = compact
        if indent + line.count <= width { return line }
        let inner = String(repeating: " ", count: indent + 2)
        let outer = String(repeating: " ", count: indent)
        switch self {
        case let .array(items):
            let body = items.map { inner + $0.text(indent: indent + 2, width: width) }
            return "[\n\(body.joined(separator: ",\n"))\n\(outer)]"
        case let .object(pairs):
            let body = pairs.map { key, value in
                inner + "\(Self.quoted(key)): " + value.text(indent: indent + 2, width: width)
            }
            return "{\n\(body.joined(separator: ",\n"))\n\(outer)}"
        default:
            return line
        }
    }

    private var compact: String {
        switch self {
        case let .string(value): Self.quoted(value)
        case let .int(value): String(value)
        case let .double(value):
            value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case let .bool(value): String(value)
        case let .array(items): "[\(items.map(\.compact).joined(separator: ", "))]"
        case let .object(pairs):
            pairs.isEmpty ? "{}"
                : "{ \(pairs.map { "\(Self.quoted($0)): \($1.compact)" }.joined(separator: ", ")) }"
        }
    }

    private static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default:
                if scalar.value < 32 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}

/// Reads one JSON object, naming the place of a problem and refusing unknown keys.
struct JSONReader {
    let place: String
    private let values: [String: Any]
    private var used: Set<String> = []

    init(_ value: Any, _ place: String) throws {
        guard let values = value as? [String: Any] else {
            throw LayoutError(description: "\(place) must be an object")
        }
        self.values = values
        self.place = place
    }

    static func parse(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        } catch {
            throw LayoutError(description: "the file is not valid JSON")
        }
    }

    func fail(_ message: String) -> LayoutError { LayoutError(description: "\(place): \(message)") }

    mutating func raw(_ key: String) -> Any? {
        used.insert(key)
        return values[key]
    }

    private mutating func typed<T>(_ key: String, _ kind: String, _ convert: (Any) -> T?) throws -> T? {
        guard let value = raw(key) else { return nil }
        guard let result = convert(value) else { throw fail("\"\(key)\" must be \(kind)") }
        return result
    }

    private static func isBool(_ value: Any) -> Bool {
        (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    }

    static func integer(_ value: Any) -> Int? {
        guard !isBool(value), let number = value as? NSNumber, let result = Int(exactly: number.doubleValue)
        else { return nil }
        return result
    }

    static func number(_ value: Any) -> Double? {
        guard !isBool(value), let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    mutating func string(_ key: String) throws -> String? { try typed(key, "a string") { $0 as? String } }
    mutating func int(_ key: String) throws -> Int? { try typed(key, "a whole number", Self.integer) }
    mutating func double(_ key: String) throws -> Double? { try typed(key, "a number", Self.number) }
    mutating func bool(_ key: String) throws -> Bool? {
        try typed(key, "true or false") { Self.isBool($0) ? $0 as? Bool : nil }
    }
    mutating func array(_ key: String) throws -> [Any]? { try typed(key, "a list") { $0 as? [Any] } }

    /// A single value, or a list with at least one.
    mutating func oneOrMany<T>(_ key: String, _ kind: String, _ convert: (Any) -> T?) throws -> [T]? {
        try typed(key, "\(kind), or a list of them") { value in
            guard let list = value as? [Any] else { return convert(value).map { [$0] } }
            let items = list.compactMap(convert)
            return !items.isEmpty && items.count == list.count ? items : nil
        }
    }

    func required<T>(_ value: T?, _ key: String) throws -> T {
        guard let value else { throw fail("has no \"\(key)\"") }
        return value
    }

    /// Call after reading every key.
    func finish() throws {
        let unknown = values.keys.filter { !used.contains($0) }.sorted()
        guard unknown.isEmpty else { throw fail("unknown key \"\(unknown[0])\"") }
    }
}
