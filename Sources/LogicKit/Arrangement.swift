import ApplicationServices

public struct Region: Codable, Sendable, Equatable {
    public let name: String?
    public let help: String?
    public let value: String?
    public let selected: Bool
}

public struct Track: Codable, Sendable, Equatable {
    public let name: String
    public let regions: [Region]
}

extension LogicApp {
    /// Tracks and regions as exposed by the arrange area. Off-screen items may be missing.
    public func tracks() throws -> [Track] {
        guard let window = projectWindow?.element,
              let contents = window.first(where: {
                  $0.role == kAXGroupRole && $0.string(kAXDescriptionAttribute) == "Tracks contents"
              }) else {
            throw LogicError("The Tracks area was not found.")
        }
        return contents.children
            .filter { $0.role == "AXLayoutArea" && $0.string(kAXDescriptionAttribute)?.hasPrefix("Track ") == true }
            .map { lane in
                Track(
                    name: lane.string(kAXDescriptionAttribute) ?? "",
                    regions: lane.children.filter { $0.role == "AXLayoutItem" }.map { item in
                        Region(
                            name: item.string(kAXDescriptionAttribute),
                            help: item.string(kAXHelpAttribute),
                            value: item.string(kAXValueAttribute),
                            selected: item.bool(kAXSelectedAttribute) ?? false
                        )
                    }
                )
            }
    }
}
