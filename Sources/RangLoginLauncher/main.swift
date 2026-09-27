import AppKit

let bundleID = "com.rang.colorpicker"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
    var appURL = Bundle.main.bundleURL
    for _ in 0..<4 { appURL.deleteLastPathComponent() }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--login"]
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
        exit(EXIT_SUCCESS)
    }
    RunLoop.main.run()
}
