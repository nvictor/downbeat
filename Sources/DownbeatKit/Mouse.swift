import ApplicationServices
import Foundation

extension LogicApp {
    /// Clicks a point, only if it still belongs to `element` and not to a window above it.
    func click(_ point: CGPoint, on element: AXElement, count: Int = 1) throws {
        try activate()
        // Right after coming to the front, the first click may only raise the window.
        Thread.sleep(forTimeInterval: 0.6)
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit
        )
        guard let hit, element.first(maxDepth: 2, where: { CFEqual($0.raw, hit) }) != nil else {
            throw DownbeatError("""
                The spot to click is covered or scrolled out of view. \
                Show it in Logic Pro, and keep hands off keyboard and mouse.
                """)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for number in 1...count {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(number))
                event?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    /// Turns the scroll wheel over the middle of `area`, only if nothing covers that spot.
    func scroll(_ area: AXElement, by pixels: CGFloat) throws {
        try activate()
        guard let frame = area.frame else { return }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit
        )
        var ancestor = hit.map { AXElement(raw: $0) }
        while let current = ancestor, !current.isSame(as: area) {
            ancestor = current.element(kAXParentAttribute)
        }
        guard ancestor != nil else {
            throw DownbeatError("The track list is covered. Keep hands off keyboard and mouse.")
        }
        let event = CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
            units: .pixel, wheelCount: 1, wheel1: Int32(pixels), wheel2: 0, wheel3: 0
        )
        event?.location = point
        event?.post(tap: .cghidEventTap)
    }
}
