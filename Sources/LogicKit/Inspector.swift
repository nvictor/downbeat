import ApplicationServices

public struct Node: Codable, Sendable {
    public let role: String
    public let subrole: String?
    public let identifier: String?
    public let title: String?
    public let label: String?
    public let value: String?
    public let selected: Bool?
    public let frame: [Int]?
    public let childCount: Int
    public let children: [Node]
}

extension LogicApp {
    /// The accessibility tree of every window, or of the menu bar.
    public func inspect(menus: Bool, depth: Int) -> [Node] {
        let roots = menus ? [root.element(kAXMenuBarAttribute)].compactMap { $0 } : root.windows
        return roots.map { Self.node($0, depth: depth) }
    }

    private static func node(_ element: AXElement, depth: Int) -> Node {
        let children = element.children
        return Node(
            role: element.role,
            subrole: element.subrole,
            identifier: element.identifier,
            title: element.title.nonEmpty,
            label: element.string(kAXDescriptionAttribute).nonEmpty,
            value: element.string(kAXValueAttribute).nonEmpty,
            selected: element.bool(kAXSelectedAttribute),
            frame: element.frame.map { [Int($0.minX), Int($0.minY), Int($0.width), Int($0.height)] },
            childCount: children.count,
            children: depth > 0 ? children.map { node($0, depth: depth - 1) } : []
        )
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.isEmpty == false ? self : nil }
}
