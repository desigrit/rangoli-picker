import AppKit
import RangCore

/// Opt-in, local integration check. A separate fixture process draws known
/// foreground colors; the normal sampler must read those through Rangoli's UI.
@MainActor
enum SamplingDiagnostics {
    private static var fixtureWindows: [NSWindow] = []

    private final class PatternView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            for (rect, color) in [
                (NSRect(x: 0, y: 0, width: 80, height: 80), NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
                (NSRect(x: 80, y: 0, width: 80, height: 80), NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
                (NSRect(x: 0, y: 80, width: 80, height: 80), NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)),
                (NSRect(x: 80, y: 80, width: 80, height: 80), NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1))
            ] {
                color.setFill()
                rect.fill()
            }
            let scale = window?.backingScaleFactor ?? 1
            NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).setFill()
            NSRect(x: 30, y: 30, width: 1 / scale, height: 1 / scale).fill()
        }
    }

    private static func panel(frame: NSRect, color: NSColor, level: Int) -> NSPanel {
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = color
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + level)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    static func showFixture(readyURL: URL) throws {
        guard let screen = NSScreen.screens.first else { throw SamplingError.displayUnavailable }
        let frame = NSRect(x: screen.frame.minX + 80, y: screen.frame.minY + 80, width: 240, height: 240)
        let back = panel(frame: frame, color: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), level: 5)
        let front = panel(frame: frame.insetBy(dx: 40, dy: 40), color: .red, level: 6)
        front.contentView = PatternView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
        fixtureWindows = [back, front]
        back.orderFrontRegardless()
        front.orderFrontRegardless()
        front.contentView?.displayIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let data = try! JSONSerialization.data(withJSONObject: ["x": frame.minX, "y": frame.minY])
            try! data.write(to: readyURL, options: .atomic)
        }
    }

    static func run(reportURL: URL) async -> Bool {
        var results: [[String: Any]] = []
        let readyURL = reportURL.deletingLastPathComponent().appendingPathComponent("fixture-\(UUID().uuidString).json")
        let fixtureURL = reportURL.deletingLastPathComponent().appendingPathComponent("RangSamplingFixture-\(UUID().uuidString)")
        let fixture = Process()
        var cover: NSPanel?
        defer {
            cover?.orderOut(nil)
            if fixture.isRunning { fixture.terminate(); fixture.waitUntilExit() }
            try? FileManager.default.removeItem(at: readyURL)
            try? FileManager.default.removeItem(at: fixtureURL)
        }
        do {
            guard CGPreflightScreenCaptureAccess() else {
                throw NSError(domain: "Rangoli.Check", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission is needed before this check."])
            }
            try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // A second process inside the same .app can be grouped into the
            // excluded application by WindowServer. Run the fixture outside
            // Rangoli's bundle so it represents a separate foreground application.
            guard let executableURL = Bundle.main.executableURL else { throw SamplingError.imageUnavailable }
            try FileManager.default.copyItem(at: executableURL, to: fixtureURL)
            fixture.executableURL = fixtureURL
            fixture.arguments = ["--sampling-fixture", readyURL.path]
            try fixture.run()
            for _ in 0..<60 {
                if FileManager.default.fileExists(atPath: readyURL.path) { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let data = try Data(contentsOf: readyURL)
            let origin = try JSONSerialization.jsonObject(with: data) as! [String: Double]
            guard let screen = NSScreen.screens.first else { throw SamplingError.displayUnavailable }
            let x = origin["x"]!, y = origin["y"]!
            let scale = screen.backingScaleFactor
            // An opaque window belonging to the sampling process must be excluded.
            cover = panel(frame: NSRect(x: x, y: y, width: 240, height: 240), color: .black, level: 7)
            cover?.orderFrontRegardless()
            let sampler = ScreenSampler()
            try await sampler.prepare()
            let cases: [(String, CGPoint, UInt32)] = [
                ("Background visible beside foreground", CGPoint(x: x + 10, y: y + 10), 0x0000FF),
                ("Foreground lower left", CGPoint(x: x + 60, y: y + 60), 0xFF0000),
                ("Foreground lower right", CGPoint(x: x + 160, y: y + 60), 0x00FF00),
                ("Foreground upper left", CGPoint(x: x + 60, y: y + 160), 0xFFFF00),
                ("Foreground upper right", CGPoint(x: x + 160, y: y + 160), 0x00FFFF),
                ("Pixel left of color boundary", CGPoint(x: x + 120 - 0.5 / scale, y: y + 60), 0xFF0000),
                ("Pixel right of color boundary", CGPoint(x: x + 120 + 0.5 / scale, y: y + 60), 0x00FF00),
                ("Single physical pixel", CGPoint(x: x + 70 + 0.5 / scale, y: y + 70 + 0.5 / scale), 0xFF00FF),
                ("Neighbor of single pixel", CGPoint(x: x + 70 + 1.5 / scale, y: y + 70 + 0.5 / scale), 0xFF0000)
            ]
            for (name, point, hex) in cases {
                let actual = try await sampler.sample(at: point, on: screen)
                let expected = SampledColor(hex: hex)
                let passed = abs(Int(actual.red) - Int(expected.red)) <= 2
                    && abs(Int(actual.green) - Int(expected.green)) <= 2
                    && abs(Int(actual.blue) - Int(expected.blue)) <= 2
                results.append(["name": name, "expected": expected.hex, "actual": actual.hex, "passed": passed])
            }
            sampler.reset()
            results.append(["name": "Cursor hotspot matches drawn tip", "passed": PickerCursor.cursor.hotSpot == PickerCursor.tip])
            let cursorRecovers = try await PickerController().checkCursorRestoration()
            results.append(["name": "Cursor recovers from repeated resets and releases on dismissal", "passed": cursorRecovers])
            let passed = results.allSatisfy { $0["passed"] as? Bool == true }
            let report: [String: Any] = ["passed": passed, "scale": scale, "checks": results]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
            return passed
        } catch {
            let report: [String: Any] = ["passed": false, "error": error.localizedDescription, "checks": results]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: reportURL)
            }
            return false
        }
    }
}
