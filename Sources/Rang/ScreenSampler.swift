import AppKit
import CoreVideo
import ScreenCaptureKit
import RangCore

enum SamplingError: LocalizedError {
    case displayUnavailable
    case imageUnavailable
    case unexpectedImageSize

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return "The display under the pointer is unavailable for capture."
        case .imageUnavailable: return "Rangoli could not read the pixel under the pointer."
        case .unexpectedImageSize: return "macOS returned an unexpected capture size. Please start picking again."
        }
    }
}

@MainActor
final class ScreenSampler {
    private var filters: [CGDirectDisplayID: SCContentFilter] = [:]

    func reset() { filters.removeAll() }

    func prepare() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Exclude Rangoli's UI by process identity; keep every other application's
        // visible foreground windows in the display composite.
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        filters = Dictionary(uniqueKeysWithValues: content.displays.map { display in
            (display.displayID, SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: []))
        })
    }

    func sample(at point: NSPoint, on screen: NSScreen) async throws -> SampledColor {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let filter = filters[number.uint32Value] else {
            throw SamplingError.displayUnavailable
        }

        let region = SamplingRegion(point: point, screenFrame: screen.frame,
                                    scale: CGFloat(filter.pointPixelScale))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.sourceRect
        configuration.width = region.pixelWidth
        configuration.height = region.pixelHeight
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB as CFString

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard image.width == region.pixelWidth, image.height == region.pixelHeight else {
            throw SamplingError.unexpectedImageSize
        }
        // Crop exactly one pixel before color conversion. Never shrink the
        // captured image into one pixel, which can average neighboring colors.
        guard let pixel = image.cropping(to: CGRect(x: region.pixelX, y: region.pixelY, width: 1, height: 1)) else {
            throw SamplingError.imageUnavailable
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw SamplingError.imageUnavailable }
        var pixels = [UInt8](repeating: 0, count: 4)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard didDraw else { throw SamplingError.imageUnavailable }
        return SampledColor(red: pixels[0], green: pixels[1], blue: pixels[2])
    }
}
