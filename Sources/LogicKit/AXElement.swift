import ApplicationServices
import Foundation

public struct LogicError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// A thin wrapper around `AXUIElement`.
struct AXElement {
    let raw: AXUIElement

    static func application(pid: pid_t) -> AXElement {
        let element = AXElement(raw: AXUIElementCreateApplication(pid))
        AXUIElementSetMessagingTimeout(element.raw, 5)
        return element
    }

    func value(_ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(raw, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    func string(_ attribute: String) -> String? {
        switch value(attribute) {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    func bool(_ attribute: String) -> Bool? {
        (value(attribute) as? NSNumber)?.boolValue
    }

    func element(_ attribute: String) -> AXElement? {
        guard let result = value(attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return AXElement(raw: result as! AXUIElement)
    }

    func elements(_ attribute: String) -> [AXElement] {
        (value(attribute) as? [AXUIElement] ?? []).map(AXElement.init(raw:))
    }

    var children: [AXElement] { elements(kAXChildrenAttribute) }
    var windows: [AXElement] { elements(kAXWindowsAttribute) }
    var role: String { string(kAXRoleAttribute) ?? "?" }
    var subrole: String? { string(kAXSubroleAttribute) }
    var identifier: String? { string(kAXIdentifierAttribute) }
    var title: String? { string(kAXTitleAttribute) }

    var frame: CGRect? {
        guard let position = value(kAXPositionAttribute), let size = value(kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    func perform(_ action: String) throws {
        let status = AXUIElementPerformAction(raw, action as CFString)
        guard status == .success else {
            throw LogicError("\(action) failed on \(role) \(title ?? identifier ?? "") (AXError \(status.rawValue))")
        }
    }

    func set(_ attribute: String, to value: CFTypeRef) throws {
        let status = AXUIElementSetAttributeValue(raw, attribute as CFString, value)
        guard status == .success else {
            throw LogicError("setting \(attribute) failed on \(role) \(identifier ?? "") (AXError \(status.rawValue))")
        }
    }

    func isSame(as other: AXElement) -> Bool { CFEqual(raw, other.raw) }

    /// Depth-first search of this element and its descendants.
    func first(maxDepth: Int = 12, where matches: (AXElement) -> Bool) -> AXElement? {
        if matches(self) { return self }
        guard maxDepth > 0 else { return nil }
        for child in children {
            if let found = child.first(maxDepth: maxDepth - 1, where: matches) { return found }
        }
        return nil
    }
}
