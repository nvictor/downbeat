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
        let strip = try wait("the channel strip of \(name)", seconds: 3) {
            projectWindow?.element.first {
                $0.role == "AXLayoutArea" && $0.string(kAXDescriptionAttribute) == "Mixer"
            }?.children.first { $0.string(kAXDescriptionAttribute) == name }
        }
        let takesMIDI = strip.first(maxDepth: 3) {
            ["MIDI plug-in", "midi assign knob"].contains($0.string(kAXDescriptionAttribute))
        }
        guard takesMIDI != nil else {
            throw DownbeatError("\(name) is not a software instrument or external MIDI track.")
        }
    }

    private func showInspector() throws {
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
