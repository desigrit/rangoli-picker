import CoreGraphics

/// A native-resolution tile and the exact pixel to read inside it.
/// AppKit positions use global, bottom-left coordinates; capture rectangles
/// use display-local, top-left coordinates in points.
public struct SamplingRegion {
    public let sourceRect: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let pixelX: Int
    public let pixelY: Int

    public init(point: CGPoint, screenFrame: CGRect, scale: CGFloat, tileSize: Int = 32) {
        precondition(scale > 0 && tileSize > 0 && screenFrame.width > 0 && screenFrame.height > 0)
        let displayWidth = max(1, Int((screenFrame.width * scale).rounded()))
        let displayHeight = max(1, Int((screenFrame.height * scale).rounded()))
        let x = min(displayWidth - 1, max(0, Int(floor((point.x - screenFrame.minX) * scale))))
        let y = min(displayHeight - 1, max(0, Int(floor((screenFrame.maxY - point.y) * scale))))
        pixelWidth = min(tileSize, displayWidth)
        pixelHeight = min(tileSize, displayHeight)
        // ScreenCaptureKit crops in points. Align the tile to whole points so
        // a half-point crop cannot shift or interpolate a Retina pixel.
        let originX = min(max(0, Int(floor(CGFloat(x - pixelWidth / 2) / scale) * scale)), displayWidth - pixelWidth)
        let originY = min(max(0, Int(floor(CGFloat(y - pixelHeight / 2) / scale) * scale)), displayHeight - pixelHeight)
        sourceRect = CGRect(x: CGFloat(originX) / scale, y: CGFloat(originY) / scale,
                            width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        pixelX = x - originX
        pixelY = y - originY
    }
}
