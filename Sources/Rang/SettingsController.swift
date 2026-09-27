import AppKit
import ServiceManagement

private final class SettingsSurface: NSView {
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onRecorded: ((Shortcut) -> Void)?
    var onInvalid: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var recording = false

    override var acceptsFirstResponder: Bool { true }

    func beginRecording() {
        recording = true
        title = "Type keys…"
        window?.makeFirstResponder(self)
    }

    func show(_ shortcut: Shortcut) {
        recording = false
        title = shortcut.displayText
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { onCancel?(); return }
        guard let shortcut = Shortcut(event: event) else { onInvalid?(); return }
        recording = false
        onRecorded?(shortcut)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned && recording { onCancel?() }
        return resigned
    }
}

@MainActor
final class SettingsController: NSViewController {
    private let hotKey: HotKeyManager
    private let loginService = SMAppService.loginItem(identifier: "com.rang.colorpicker.login")
    private let recorder = ShortcutRecorderButton(frame: .zero)
    private let loginSwitch = NSSwitch(frame: .zero)
    private let message = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()

    init(hotKey: HotKeyManager) {
        self.hotKey = hotKey
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = SettingsSurface(frame: NSRect(x: 0, y: 0, width: 248, height: 84))
        root.setAccessibilityLabel("Rangoli settings")
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.spacing = 0
        rows.alignment = .leading
        rows.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(rows)
        rows.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        recorder.bezelStyle = .rounded
        recorder.controlSize = .small
        recorder.font = .systemFont(ofSize: 13, weight: .medium)
        recorder.target = self
        recorder.action = #selector(recordShortcut)
        recorder.show(hotKey.shortcut)
        recorder.setAccessibilityLabel("Change keyboard shortcut")
        recorder.toolTip = "Click to record a new shortcut"
        recorder.onRecorded = { [weak self] shortcut in
            guard let self else { return }
            let result = self.hotKey.register(shortcut)
            if result != noErr { self.hotKey.resume() }
            self.recorder.show(self.hotKey.shortcut)
            self.setMessage(result == noErr ? "" : "That shortcut is unavailable. Your previous shortcut is still set.", error: result != noErr)
        }
        recorder.onInvalid = { [weak self] in self?.setMessage("Include ⌘, ⌥, or ⌃ with a key. Esc cancels.") }
        recorder.onCancel = { [weak self] in self?.cancelRecording() }
        rows.addArrangedSubview(row(title: "Shortcut", control: recorder, controlWidth: 80))
        loginSwitch.state = loginIsRequested ? .on : .off
        loginSwitch.controlSize = .small
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)
        loginSwitch.setAccessibilityLabel("Launch at login")
        rows.addArrangedSubview(row(title: "Launch at login", control: loginSwitch, controlWidth: 38))

        message.font = .systemFont(ofSize: 11)
        message.textColor = .secondaryLabelColor
        message.isHidden = true
        message.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        view = root
        if hotKey.registrationError != nil { setMessage("Shortcut unavailable. Click the keys to choose another.", error: true) }
    }

    private func row(title: String, control: NSView, controlWidth: CGFloat) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 224).isActive = true
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        for item in [label, control] { item.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(item) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: controlWidth),
            control.heightAnchor.constraint(equalToConstant: 26),
            label.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -8)
        ])
        return row
    }

    private func setMessage(_ text: String, error: Bool = false) {
        message.stringValue = text
        message.textColor = error ? .systemRed : .secondaryLabelColor
        message.isHidden = text.isEmpty
        resizeToContent()
    }

    private func resizeToContent() {
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: 248, height: stack.fittingSize.height + 24)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
        loginSwitch.state = loginIsRequested ? .on : .off
        resizeToContent()
    }

    override func viewWillDisappear() {
        cancelRecording()
        super.viewWillDisappear()
    }

    @objc private func recordShortcut() {
        hotKey.suspend()
        recorder.beginRecording()
        setMessage("Press your shortcut. Esc cancels.")
    }

    private func cancelRecording() {
        guard recorder.recording else { return }
        hotKey.resume()
        recorder.show(hotKey.shortcut)
        setMessage("")
    }

    @objc private func toggleLogin() {
        do {
            if loginSwitch.state == .on { try loginService.register() }
            else { try loginService.unregister() }
            setMessage(loginService.status == .requiresApproval ? "Allow Rangoli in System Settings → Login Items." : "")
        } catch {
            loginSwitch.state = loginIsRequested ? .on : .off
            setMessage(error.localizedDescription, error: true)
        }
    }

    private var loginIsRequested: Bool {
        loginService.status == .enabled || loginService.status == .requiresApproval
    }

    #if DEBUG
    func renderDesignPreview(to directory: URL) throws {
        loadViewIfNeeded()
        resizeToContent()
        view.setFrameSize(preferredContentSize)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("settings.png"))
    }
    #endif
}
