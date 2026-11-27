import ArgumentParser
import DownbeatKit

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Dump the Logic Pro accessibility tree.")

    @Flag(help: "Inspect the menu bar instead of the windows.")
    var menus = false

    @Flag(help: "Print an indented tree (default).")
    var tree = false

    @Flag(help: "Print JSON.")
    var json = false

    @Option(help: "Levels below each root.")
    var depth = 4

    func validate() throws {
        if tree && json { throw ValidationError("Use --tree or --json, not both.") }
    }

    func run() throws {
        let nodes = try LogicApp().inspect(menus: menus, depth: depth)
        if json {
            try printJSON(nodes)
        } else {
            nodes.forEach { show($0, indent: 0) }
        }
    }

    private func show(_ node: Node, indent: Int) {
        var parts = [node.role]
        if let subrole = node.subrole { parts.append("(\(subrole))") }
        if let identifier = node.identifier { parts.append("#\(identifier)") }
        if let title = node.title { parts.append("title=\(title.debugDescription)") }
        if let label = node.label { parts.append("label=\(label.debugDescription)") }
        if let value = node.value { parts.append("value=\(value.prefix(80).debugDescription)") }
        if node.selected == true { parts.append("selected") }
        if node.children.isEmpty && node.childCount > 0 { parts.append("[\(node.childCount) children]") }
        print(String(repeating: "  ", count: indent) + parts.joined(separator: " "))
        node.children.forEach { show($0, indent: indent + 1) }
    }
}
