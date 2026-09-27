import Foundation

public enum ColorFormat: String, CaseIterable, Sendable {
    case hex = "HEX"
    case rgb = "RGB"
    case hsl = "HSL"
    case hsv = "HSV"
    case cmyk = "CMYK"
    case lab = "Lab"
}

public struct SampledColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(red: UInt8((hex >> 16) & 0xff),
                  green: UInt8((hex >> 8) & 0xff),
                  blue: UInt8(hex & 0xff))
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public func formatted(as format: ColorFormat) -> String {
        let r = Double(red) / 255
        let g = Double(green) / 255
        let b = Double(blue) / 255
        let maxComponent = max(r, g, b)
        let minComponent = min(r, g, b)
        let delta = maxComponent - minComponent

        switch format {
        case .hex:
            return hex
        case .rgb:
            return "rgb(\(red), \(green), \(blue))"
        case .hsl:
            let hue = hueDegrees(r: r, g: g, b: b, maximum: maxComponent, delta: delta)
            let lightness = (maxComponent + minComponent) / 2
            let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
            return "hsl(\(Int(hue.rounded()) % 360)°, \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
        case .hsv:
            let hue = hueDegrees(r: r, g: g, b: b, maximum: maxComponent, delta: delta)
            let saturation = maxComponent == 0 ? 0 : delta / maxComponent
            return "hsv(\(Int(hue.rounded()) % 360)°, \(Int((saturation * 100).rounded()))%, \(Int((maxComponent * 100).rounded()))%)"
        case .cmyk:
            let black = 1 - maxComponent
            if black >= 1 {
                return "cmyk(0%, 0%, 0%, 100%)"
            }
            let cyan = (1 - r - black) / (1 - black)
            let magenta = (1 - g - black) / (1 - black)
            let yellow = (1 - b - black) / (1 - black)
            return "cmyk(\(Int((cyan * 100).rounded()))%, \(Int((magenta * 100).rounded()))%, \(Int((yellow * 100).rounded()))%, \(Int((black * 100).rounded()))%)"
        case .lab:
            let lab = labD50
            return String(format: "lab(%.1f%% %.1f %.1f)", locale: Locale(identifier: "en_US_POSIX"), lab.lightness, lab.a, lab.b)
        }
    }

    private func hueDegrees(r: Double, g: Double, b: Double, maximum: Double, delta: Double) -> Double {
        guard delta > 0 else { return 0 }
        let sector: Double
        if maximum == r {
            sector = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == g {
            sector = (b - r) / delta + 2
        } else {
            sector = (r - g) / delta + 4
        }
        return (sector * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    public var labD50: LabColor {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linear(red)
        let g = linear(green)
        let b = linear(blue)
        let x65 = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let y65 = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z65 = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
        let x50 = 1.0478112 * x65 + 0.0228866 * y65 - 0.0501270 * z65
        let y50 = 0.0295424 * x65 + 0.9904844 * y65 - 0.0170491 * z65
        let z50 = -0.0092345 * x65 + 0.0150436 * y65 + 0.7521316 * z65
        func f(_ value: Double) -> Double {
            let threshold = 216.0 / 24389.0
            return value > threshold ? cbrt(value) : (24389.0 / 27.0 * value + 16) / 116
        }
        let fx = f(x50 / 0.96422)
        let fy = f(y50)
        let fz = f(z50 / 0.82521)
        return LabColor(lightness: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    fileprivate var oklab: OKLabColor {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linear(red)
        let g = linear(green)
        let b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return OKLabColor(lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                          a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                          b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }
}

public struct LabColor: Equatable, Sendable {
    public let lightness: Double
    public let a: Double
    public let b: Double
}

fileprivate struct OKLabColor {
    let lightness: Double
    let a: Double
    let b: Double

    func distanceSquared(to other: OKLabColor) -> Double {
        pow(lightness - other.lightness, 2) + pow(a - other.a, 2) + pow(b - other.b, 2)
    }
}

public enum CSSColorNames {
    private static let entries: [(name: String, color: OKLabColor)] = CSSColorTable.entries.map {
        ($0.name, SampledColor(hex: $0.hex).oklab)
    }

    public static var count: Int { entries.count }

    public static func nearest(to color: SampledColor) -> String {
        let sample = color.oklab
        guard let match = entries.min(by: { sample.distanceSquared(to: $0.color) < sample.distanceSquared(to: $1.color) }) else {
            return "Unknown"
        }
        return match.name
    }
}
