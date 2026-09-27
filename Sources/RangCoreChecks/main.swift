import Foundation
import CoreGraphics
import RangCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

func near(_ actual: Double, _ expected: Double, tolerance: Double = 0.3) -> Bool {
    abs(actual - expected) <= tolerance
}

let red = SampledColor(hex: 0xFF0000)
check(red.formatted(as: .hex) == "#FF0000", "Hex formatting")
check(red.formatted(as: .rgb) == "rgb(255, 0, 0)", "RGB formatting")
check(red.formatted(as: .hsl) == "hsl(0°, 100%, 50%)", "HSL formatting")
check(red.formatted(as: .hsv) == "hsv(0°, 100%, 100%)", "HSV formatting")
check(red.formatted(as: .cmyk) == "cmyk(0%, 100%, 100%, 0%)", "CMYK formatting")
check(SampledColor(hex: 0).formatted(as: .cmyk) == "cmyk(0%, 0%, 0%, 100%)", "Black CMYK")

let whiteLab = SampledColor(hex: 0xFFFFFF).labD50
check(near(whiteLab.lightness, 100, tolerance: 0.02), "D50 white lightness")
check(near(whiteLab.a, 0, tolerance: 0.02), "D50 white a")
check(near(whiteLab.b, 0, tolerance: 0.02), "D50 white b")
let redLab = red.labD50
check(near(redLab.lightness, 54.29), "D50 red lightness")
check(near(redLab.a, 80.81), "D50 red a")
check(near(redLab.b, 69.89), "D50 red b")

check(CSSColorNames.count == 148, "CSS Color 4 named-color table")
check(CSSColorNames.nearest(to: SampledColor(hex: 0xA52A2A)) == "Brown", "Exact Brown name")
check(CSSColorNames.nearest(to: SampledColor(hex: 0xAFEEEE)) == "Pale Turquoise", "Spaced Pale Turquoise name")
check(CSSColorNames.nearest(to: SampledColor(hex: 0x000000)) == "Black", "Exact Black name")
check(CSSColorNames.nearest(to: SampledColor(hex: 0x2F4F4F)) == "Dark Slate Gray", "Spaced Dark Slate Gray name")
check(CSSColorNames.nearest(to: SampledColor(hex: 0x191970)) == "Midnight Blue", "Spaced Midnight Blue name")
check(CSSColorNames.nearest(to: SampledColor(hex: 0xFAFAD2)) == "Light Goldenrod Yellow", "Long spaced name")

let displayFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
let retina = SamplingRegion(point: CGPoint(x: 100.25, y: 200.25), screenFrame: displayFrame, scale: 2)
check(retina.sourceRect.minX * 2 + CGFloat(retina.pixelX) == 200, "Retina x maps to exact physical pixel")
check(retina.sourceRect.minY * 2 + CGFloat(retina.pixelY) == 1399, "AppKit y flips to top-left pixel")
check(retina.sourceRect.width * 2 == CGFloat(retina.pixelWidth), "Tile remains at native resolution")
let oddRetinaPixel = SamplingRegion(point: CGPoint(x: 100.75, y: 200.25), screenFrame: displayFrame, scale: 2)
check(oddRetinaPixel.sourceRect.minX.rounded(.down) == oddRetinaPixel.sourceRect.minX,
      "Retina crop x avoids half-point interpolation")
check(oddRetinaPixel.sourceRect.minY.rounded(.down) == oddRetinaPixel.sourceRect.minY,
      "Retina crop y avoids half-point interpolation")
check(oddRetinaPixel.sourceRect.minX * 2 + CGFloat(oddRetinaPixel.pixelX) == 201,
      "Whole-point crop preserves odd Retina pixel x")
let otherDisplay = SamplingRegion(point: CGPoint(x: -1200, y: 300),
                                  screenFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), scale: 1)
check(otherDisplay.sourceRect.minX + CGFloat(otherDisplay.pixelX) == 720, "Secondary display x offset")
check(otherDisplay.sourceRect.minY + CGFloat(otherDisplay.pixelY) == 580, "Secondary display y offset")
for point in [CGPoint(x: 0, y: 900), CGPoint(x: 1440, y: 0)] {
    let edge = SamplingRegion(point: point, screenFrame: displayFrame, scale: 2)
    check(edge.sourceRect.minX >= 0 && edge.sourceRect.maxX <= displayFrame.width, "Tile fits at horizontal edge")
    check(edge.sourceRect.minY >= 0 && edge.sourceRect.maxY <= displayFrame.height, "Tile fits at vertical edge")
    check(edge.pixelX >= 0 && edge.pixelX < edge.pixelWidth, "Edge pixel x is in tile")
    check(edge.pixelY >= 0 && edge.pixelY < edge.pixelHeight, "Edge pixel y is in tile")
}

// Exercise the actual active-session timer with changing pointer positions.
// This catches the regression where the preview receives only its initial pixel.
var pointer = CGPoint(x: 120, y: 80)
var reads = 0
var maintenanceTicks = 0
var positions: [CGPoint] = []
let tracker = PointerTracker(interval: 0.005, readPosition: {
    reads += 1
    return pointer
}, onTick: { _ in maintenanceTicks += 1 }, onChange: { positions.append($0) })
tracker.start()
check(positions == [pointer], "Initial pointer delivered immediately")
pointer = CGPoint(x: 380, y: 220)
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
check(positions.last == pointer, "Pointer follows movement without mouse events")
check(positions.count == 2, "Stationary pointer does not request duplicate captures")
check(maintenanceTicks > positions.count, "Cursor maintenance continues while pointer is stationary")
pointer = CGPoint(x: -400, y: 1400)
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
check(positions.last == pointer, "Pointer crosses displays with negative coordinates")
tracker.stop()
let stoppedReads = reads
let stoppedMaintenanceTicks = maintenanceTicks
pointer = .zero
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
check(reads == stoppedReads, "No pointer polling after dismissal")
check(maintenanceTicks == stoppedMaintenanceTicks, "No cursor maintenance after dismissal")
tracker.start()
check(positions.last == .zero, "Pointer tracking restarts for a new pick")
tracker.stop()
print("Rang core checks passed")
