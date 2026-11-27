import ApplicationServices

/// One row of the Region inspector.
struct InspectorControl: Equatable {
    /// For example `Transpose, 0 semitones`, or `Loop` for a checkbox.
    let label: String
    /// The state of a checkbox, `0` or `1`.
    let value: String?
}

enum RegionSettings {
    /// Rows that must be readable before a region counts as untouched.
    private static let required = ["Loop", "Velocity Offset", "Transpose", "Quantize"]

    /// The settings that a round trip would bake into the notes or lose.
    /// A required row that cannot be found counts too.
    static func problems(in controls: [InspectorControl]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for control in controls {
            let parts = control.label.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = parts.first else { continue }
            let values = Array(parts.dropFirst())
            let neutral: Bool
            switch name {
            case "Loop", "Mute": neutral = control.value == "0"
            case "Velocity Offset": neutral = values == ["0"]
            case "Transpose": neutral = values == ["0 semitones"]
            case "Delay": neutral = values == ["0 ticks"]
            case "Quantize": neutral = values == ["Off"]
            // The section header shares this name and carries no value.
            case "Dynamics", "Gate Time": neutral = values.allSatisfy { $0 == "100%" }
            case "Pitch Source": neutral = values.allSatisfy { $0 == "Off" }
            default: continue
            }
            if name == "Quantize" && values.isEmpty { continue }
            seen.insert(name)
            if !neutral {
                result.append(values.isEmpty ? "\(name) is on" : "\(name) is \(values.joined(separator: ", "))")
            }
        }
        result += required.filter { !seen.contains($0) }.map { "\($0) could not be read" }
        return result
    }
}

extension LogicApp {
    /// Throws if the selected region has Loop or any playback setting turned on.
    /// Opens the Region inspector when needed.
    public func requirePlainRegion() throws {
        try showRegionInspector()
        let problems = RegionSettings.problems(in: try inspectorControls())
        guard problems.isEmpty else {
            throw DownbeatError("""
                The region has settings that cannot survive a round trip: \(problems.joined(separator: "; ")). \
                Reset them in the Region inspector. Nothing was changed.
                """)
        }
    }

    /// Renames the one region that matches, through the name field of the Region inspector.
    public func renameRegion(_ reference: RegionReference, to name: String) throws -> RegionSummary {
        try Self.checkRegionName(name)
        let placement = try select(reference)
        let track = Self.trackParts(placement.track)
        func renamed() throws -> RegionSummary? {
            try regionSummaries().first { $0.trackNumber == track.number && $0.startBar == placement.startBar }
        }
        guard let region = try renamed() else { throw DownbeatError("The region was not found.") }
        if region.name == name { return region }
        let editor = try openRegionNameEditor(showing: region.name)
        try editor.set(kAXValueAttribute, to: name as CFString)
        try wait("the new name to be accepted") { editor.string(kAXValueAttribute) == name ? true : nil }
        try sendKey(Key.returnKey)
        return try wait("the region to be renamed") { try renamed().flatMap { $0.name == name ? $0 : nil } }
    }

    public static func checkRegionName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !name.contains(where: \.isNewline) else {
            throw DownbeatError("A region name cannot be empty or span lines.")
        }
    }

    /// Double-clicks the name next to "Region:" until it turns into an editor.
    ///
    /// Keys typed outside an edit field act as Logic Pro key commands, so nothing is typed:
    /// the caller writes the name into the editor, which is returned only once it is open.
    private func openRegionNameEditor(showing name: String) throws -> AXElement {
        try showRegionInspector()
        for _ in 1...3 {
            guard let inspector = regionInspector, let label = inspector.children.first(where: {
                $0.role == kAXStaticTextRole && $0.string(kAXValueAttribute) == name
            }), let frame = label.frame else { break }
            try click(CGPoint(x: frame.minX + min(frame.width / 2, 20), y: frame.midY), on: inspector, count: 2)
            let editor = try? wait("the name editor", seconds: 2) { () -> AXElement? in
                guard let focused = root.element(kAXFocusedUIElementAttribute),
                      focused.role == kAXTextFieldRole,
                      focused.isSettable(kAXValueAttribute),
                      focused.string(kAXValueAttribute) == name else { return nil }
                return focused
            }
            if let editor { return editor }
        }
        throw DownbeatError("The name editor of \(name) did not open. Nothing was renamed.")
    }

    /// The color name the Region inspector reports for the selected region.
    func regionColor() throws -> String {
        try showRegionInspector()
        return try wait("the region color", seconds: 3) {
            try inspectorControls().first { $0.label == "Color" }?.value
        }
    }

    /// Throws unless the inspector's channel strip of the selected track takes MIDI:
    /// a software instrument has a MIDI plug-in slot, an external MIDI track has assign knobs.
    func requireMIDIStrip(named name: String) throws {
        try showInspector()
        let strip = try wait("the channel strip of \(name)", seconds: 3) { channelStrip(named: name) }
        let takesMIDI = strip.first(maxDepth: 3) {
            ["MIDI plug-in", "midi assign knob"].contains($0.string(kAXDescriptionAttribute))
        }
        guard takesMIDI != nil else {
            throw DownbeatError("\(name) is not a software instrument or external MIDI track.")
        }
    }

    /// The inspector's channel strip with this name.
    func channelStrip(named name: String) -> AXElement? {
        projectWindow?.element.first {
            $0.role == "AXLayoutArea" && $0.string(kAXDescriptionAttribute) == "Mixer"
        }?.children.first { $0.string(kAXDescriptionAttribute) == name }
    }

    func showInspector() throws {
        guard let window = projectWindow?.element else { throw DownbeatError("Open a project.") }
        let toggle = window.first { $0.identifier == "controlBar/inspectorButton" }
        if let toggle, toggle.string(kAXValueAttribute) == "0" { try toggle.perform(kAXPressAction) }
    }

    private func showRegionInspector() throws {
        try showInspector()
        if regionInspector == nil {
            try wait("the Region inspector") { regionInspector }
        }
        // Each section reveals the next. "More" appears twice; the first belongs to General.
        for section in ["Region", "General", "More", "Quantize"] {
            let button = try wait("the \(section) section", seconds: 3) {
                regionInspector?.first(maxDepth: 3) {
                    $0.role == kAXButtonRole && $0.string(kAXDescriptionAttribute) == section
                }
            }
            if button.string(kAXValueAttribute) == "Collapsed" {
                try button.perform(kAXPressAction)
                try wait("the \(section) section to open") {
                    button.string(kAXValueAttribute) != "Collapsed" ? true : nil
                }
            }
        }
    }

    /// The group that holds the "Region:" heading. It reads "Region Defaults:" with no selection.
    private var regionInspector: AXElement? {
        projectWindow?.element.first(maxDepth: 12) { element in
            element.children.contains {
                $0.role == kAXStaticTextRole && $0.string(kAXValueAttribute) == "Region:"
            }
        }
    }

    private func inspectorControls() throws -> [InspectorControl] {
        guard let inspector = regionInspector else { throw DownbeatError("The Region inspector was not found.") }
        var result: [InspectorControl] = []
        func collect(_ element: AXElement, depth: Int) {
            if element.role == kAXButtonRole || element.role == kAXCheckBoxRole,
               let label = element.string(kAXDescriptionAttribute) {
                result.append(InspectorControl(label: label, value: element.string(kAXValueAttribute)))
            }
            if depth > 0 { element.children.forEach { collect($0, depth: depth - 1) } }
        }
        collect(inspector, depth: 3)
        return result
    }
}
