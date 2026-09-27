import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsPopover: NSPopover?
    private var hotKey: HotKeyManager!
    private let picker = PickerController()
    private weak var previousApplication: NSRunningApplication?
    private var starting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        hotKey = HotKeyManager()
        hotKey.onPress = { [weak self] in self?.togglePicker() }
        picker.onDismiss = { [weak self] in self?.restorePreviousApplication() }
        picker.onError = { [weak self] error in self?.showError(error) }

        if ProcessInfo.processInfo.arguments.contains("--settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        } else if !ProcessInfo.processInfo.arguments.contains("--login") {
            DispatchQueue.main.async { [weak self] in self?.startPicking() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        startPicking()
        return true
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(named: "RangoliMenu")
            ?? NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Rangoli")
        image?.size = NSSize(width: 18, height: 18)
        image?.accessibilityDescription = "Rangoli"
        statusItem.button?.image = image
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Rangoli Color Picker"
        let menu = NSMenu()
        menu.addItem(withTitle: "Pick", action: #selector(startPickingFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Rangoli", action: #selector(quit), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func startPickingFromMenu() { startPicking() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func togglePicker() {
        if picker.isActive { picker.dismiss() }
        else { startPicking() }
    }

    private func startPicking() {
        guard !picker.isActive, !starting else { return }
        settingsPopover?.close()
        previousApplication = NSWorkspace.shared.frontmostApplication

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            showPermissionAlert()
            return
        }

        starting = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.starting = false }
            do {
                try await self.picker.start()
            } catch {
                self.showError(error)
            }
        }
    }

    @objc private func showSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            if self.settingsPopover == nil {
                let popover = NSPopover()
                popover.behavior = .transient
                popover.contentViewController = SettingsController(hotKey: self.hotKey)
                self.settingsPopover = popover
            }
            if self.settingsPopover?.isShown == true { self.settingsPopover?.close() }
            else {
                self.settingsPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func restorePreviousApplication() {
        previousApplication?.activate()
        previousApplication = nil
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording access is needed"
        alert.informativeText = "Rangoli reads the pixel under the pointer only while the picker is open. Allow Rangoli in System Settings → Privacy & Security → Screen & System Audio Recording, then choose Pick again. macOS may require a relaunch after approval."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Rangoli could not sample the screen"
        alert.runModal()
    }
}

@main
enum RangMain {
    static func main() {
        let application = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--sampling-fixture"),
           CommandLine.arguments.count > index + 1 {
            application.setActivationPolicy(.accessory)
            do { try SamplingDiagnostics.showFixture(readyURL: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { exit(EXIT_FAILURE) }
            application.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--check-sampling"),
           CommandLine.arguments.count > index + 1 {
            application.setActivationPolicy(.accessory)
            Task { @MainActor in
                let passed = await SamplingDiagnostics.run(reportURL: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }
            application.run()
            return
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-design"),
           CommandLine.arguments.count > index + 1 {
            do {
                try PickerController().renderDesignPreviews(
                    to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
                try SettingsController(hotKey: HotKeyManager()).renderDesignPreview(
                    to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
            } catch {
                fputs("Design render failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }
        #endif
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
