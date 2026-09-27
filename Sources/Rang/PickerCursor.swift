import AppKit

enum PickerCursor {
    // A small white pipette with a thin black outline. The hotspot is the
    // lower-left tip in the image's top-left coordinate system.
    static let tip = NSPoint(x: 4, y: 19)
    static let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
        guard let symbol = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Pick color")?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular)) else { return false }
        func draw(_ color: NSColor, offset: NSPoint = .zero) {
            let tinted = symbol.withSymbolConfiguration(.init(paletteColors: [color]))!
            tinted.draw(in: NSRect(x: 1 + offset.x, y: 1 + offset.y, width: 20, height: 20),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }
        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 4) {
            draw(.black, offset: NSPoint(x: cos(angle) * 0.55, y: sin(angle) * 0.55))
        }
        draw(.white)
        return true
    }

    static let cursor = NSCursor(image: image, hotSpot: tip)
}
