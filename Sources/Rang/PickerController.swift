import AppKit
import RangCore

private final class CatcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DecorationImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class CatcherView: NSView {
    var onSelect: ((NSPoint) -> Void)?
    var onCancel: (() -> Void)?
    let pickerCursor: NSCursor
    private var pointerArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        pickerCursor = PickerCursor.cursor
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: pickerCursor) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                 owner: self)
        addTrackingArea(area)
        pointerArea = area
    }
    override func cursorUpdate(with event: NSEvent) { pickerCursor.set() }
    override func mouseEntered(with event: NSEvent) { pickerCursor.set() }
    override func mouseMoved(with event: NSEvent) { pickerCursor.set() }
    override func mouseDown(with event: NSEvent) { onSelect?(NSEvent.mouseLocation) }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else { super.keyDown(with: event) }
    }
}

@MainActor
final class PickerController: NSObject {
    private let sampler = ScreenSampler()
    private var catchers: [CatcherPanel] = []
    private var toolbar: NSPanel?
    private var preview: NSPanel?
    private var codeLabel: NSTextField?
    private var nameLabel: NSTextField?
    private var swatch: NSView?
    private var localKeyMonitor: Any?
    private var displayObserver: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var menuIsTracking = false
    private var captureTask: Task<Void, Never>?
    private lazy var pointerTracker = PointerTracker(
        readPosition: { NSEvent.mouseLocation },
        onTick: { [weak self] point in self?.maintainCursor(at: point) },
        onChange: { [weak self] point in self?.pointerMoved(to: point) }
    )
    private var pendingPoint: NSPoint?
    private var lastPointer: NSPoint?
    private var currentColor: SampledColor?
    private var selecting = false
    private var ready = false
    private var sessionID = 0
    private(set) var isActive = false
    private var format: ColorFormat

    var onDismiss: (() -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        format = ColorFormat(rawValue: UserDefaults.standard.string(forKey: "selectedFormat") ?? "HEX") ?? .hex
        super.init()
    }

    func start() async throws {
        guard !isActive else { return }
        sessionID += 1
        let session = sessionID
        isActive = true
        selecting = false
        ready = false
        currentColor = nil
        buildCatchers()
        buildToolbar()
        buildPreview()

        do {
            try await sampler.prepare()
            guard isActive, sessionID == session else {
                sampler.reset()
                return
            }
            ready = true
        } catch {
            dismiss()
            throw error
        }

        // Nonactivating panels take picker key events without switching away
        // from the user's foreground app (including its Space/Stage Manager set).
        catchers.first?.makeKeyAndOrderFront(nil)
        toolbar?.orderFrontRegardless()
        preview?.orderFrontRegardless()
        menuObservers = [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    self?.menuIsTracking = note.name == NSMenu.didBeginTrackingNotification
                }
            }
        }
        pointerTracker.start()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.dismiss() } }
    }

    private func configure(_ panel: NSPanel, levelOffset: Int = 0) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + levelOffset)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
    }

    private func buildCatchers() {
        catchers = NSScreen.screens.map { screen in
            let panel = CatcherPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false, screen: screen)
            configure(panel)
            panel.title = "Rangoli Screen Overlay"
            // A completely clear window can be skipped by WindowServer hit
            // testing. The imperceptible fill keeps selection clicks in Rangoli.
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.01)
            panel.ignoresMouseEvents = false
            let view = CatcherView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onSelect = { [weak self] point in self?.select(at: point) }
            view.onCancel = { [weak self] in self?.dismiss() }
            panel.contentView = view
            panel.makeFirstResponder(view)
            panel.orderFrontRegardless()
            return panel
        }
    }

    private func buildToolbar() {
        guard let primary = NSScreen.screens.first else { return }
        let size = NSSize(width: 128, height: 32)
        let visible = primary.visibleFrame
        let rect = NSRect(x: visible.midX - size.width / 2,
                          y: visible.maxY - size.height - 10,
                          width: size.width, height: size.height)
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel, levelOffset: 2)
        panel.title = "Rangoli Format"
        panel.hasShadow = true
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        styleBubble(container, radius: 9)

        let popup = NSPopUpButton(frame: NSRect(x: 8, y: 3, width: 79, height: 26), pullsDown: false)
        popup.isBordered = false
        popup.alignment = .center
        popup.font = .systemFont(ofSize: 12, weight: .semibold)
        popup.controlSize = .small
        popup.contentTintColor = NSColor(calibratedWhite: 0.18, alpha: 1)
        (popup.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        popup.addItems(withTitles: ColorFormat.allCases.map(\.rawValue))
        popup.selectItem(withTitle: format.rawValue)
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        container.addSubview(popup)

        let chevron = DecorationImageView(frame: NSRect(x: 76, y: 12, width: 8, height: 8))
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(
            .init(pointSize: 8, weight: .semibold))
        chevron.contentTintColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        container.addSubview(chevron)

        let divider = NSBox(frame: NSRect(x: 93, y: 8, width: 1, height: 16))
        divider.boxType = .separator
        container.addSubview(divider)

        let close = NSButton(frame: NSRect(x: 98, y: 4, width: 24, height: 24))
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close picker")?.withSymbolConfiguration(
            .init(pointSize: 10, weight: .medium))
        close.contentTintColor = NSColor(calibratedWhite: 0.22, alpha: 1)
        close.target = self
        close.action = #selector(closePressed)
        close.setAccessibilityLabel("Close picker")
        container.addSubview(close)

        panel.contentView = container
        toolbar = panel
    }

    private func buildPreview() {
        let size = NSSize(width: 148, height: 48)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel, levelOffset: 3)
        panel.title = "Rangoli Color Preview"
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        styleBubble(container, radius: 9)

        let sample = NSView(frame: NSRect(x: 8, y: 8, width: 32, height: 32))
        sample.wantsLayer = true
        sample.layer?.cornerRadius = 5
        sample.layer?.borderWidth = 0.5
        sample.layer?.borderColor = NSColor(calibratedWhite: 0.6, alpha: 0.4).cgColor
        container.addSubview(sample)

        let code = NSTextField(labelWithString: "Sampling…")
        code.frame = NSRect(x: 48, y: 25, width: size.width - 57, height: 16)
        code.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        code.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        code.lineBreakMode = .byTruncatingTail
        container.addSubview(code)

        let name = NSTextField(labelWithString: "")
        name.frame = NSRect(x: 48, y: 9, width: size.width - 57, height: 14)
        name.font = .systemFont(ofSize: 11, weight: .regular)
        name.textColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        name.lineBreakMode = .byTruncatingTail
        container.addSubview(name)

        panel.contentView = container
        preview = panel
        swatch = sample
        codeLabel = code
        nameLabel = name
    }

    private func styleBubble(_ view: NSView, radius: CGFloat) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1).cgColor
        view.layer?.cornerRadius = radius
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
    }

    private func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func pointerMoved(to point: NSPoint) {
        guard isActive, ready, let screen = screen(at: point) else { return }
        lastPointer = point
        positionPreview(at: point, on: screen)
        pendingPoint = point
        guard captureTask == nil else { return }
        let session = sessionID
        captureTask = Task { [weak self] in
            guard let self else { return }
            while self.isActive, self.sessionID == session, !Task.isCancelled, let nextPoint = self.pendingPoint {
                self.pendingPoint = nil
                if let nextScreen = self.screen(at: nextPoint) {
                    do {
                        let color = try await self.sampler.sample(at: nextPoint, on: nextScreen)
                        if self.isActive && self.sessionID == session && !Task.isCancelled {
                            self.updatePreview(with: color)
                        }
                    } catch {
                        if self.isActive && self.sessionID == session {
                            self.dismiss()
                            self.onError?(error)
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if self.sessionID == session { self.captureTask = nil }
        }
    }

    private func maintainCursor(at point: NSPoint) {
        guard isActive, ready, !menuIsTracking, screen(at: point) != nil else { return }
        if toolbar?.frame.contains(point) == true {
            NSCursor.arrow.set()
        } else {
            // AppKit can replace a nonactivating panel's cursor without a
            // mouse-enter event. Reassert it on the existing active-only tick.
            PickerCursor.cursor.set()
        }
    }

    private func positionPreview(at point: NSPoint, on screen: NSScreen) {
        guard let preview else { return }
        let bounds = screen.visibleFrame
        let size = preview.frame.size
        var x = point.x + 16
        var y = point.y - size.height - 16
        if x + size.width > bounds.maxX { x = point.x - size.width - 16 }
        if y < bounds.minY { y = point.y + 16 }
        x = min(max(x, bounds.minX + 6), bounds.maxX - size.width - 6)
        y = min(max(y, bounds.minY + 6), bounds.maxY - size.height - 6)
        preview.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func updatePreview(with color: SampledColor) {
        currentColor = color
        codeLabel?.stringValue = color.formatted(as: format)
        nameLabel?.stringValue = CSSColorNames.nearest(to: color)
        swatch?.layer?.backgroundColor = NSColor(srgbRed: CGFloat(color.red) / 255,
                                                 green: CGFloat(color.green) / 255,
                                                 blue: CGFloat(color.blue) / 255, alpha: 1).cgColor
        fitPreviewToContent()
    }

    private func select(at point: NSPoint) {
        guard isActive, ready, !selecting, let screen = screen(at: point) else { return }
        selecting = true
        let session = sessionID
        Task { [weak self] in
            guard let self else { return }
            do {
                let color = try await self.sampler.sample(at: point, on: screen)
                guard self.isActive, self.sessionID == session else { return }
                let text = color.formatted(as: self.format)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.dismiss()
            } catch {
                guard self.isActive, self.sessionID == session else { return }
                self.selecting = false
                self.dismiss()
                self.onError?(error)
            }
        }
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title, let newFormat = ColorFormat(rawValue: title) else { return }
        format = newFormat
        UserDefaults.standard.set(newFormat.rawValue, forKey: "selectedFormat")
        if let currentColor { updatePreview(with: currentColor) }
    }

    private func fitPreviewToContent() {
        guard let preview, let codeLabel, let nameLabel else { return }
        func fullWidth(_ label: NSTextField) -> CGFloat {
            let size = (label.stringValue as NSString).size(withAttributes: [.font: label.font!])
            return ceil(size.width) + 6 // Include the text field cell's horizontal insets.
        }
        let textWidth = max(fullWidth(codeLabel), fullWidth(nameLabel))
        let width = max(128, textWidth + 57)
        if preview.frame.width != width {
            preview.setContentSize(NSSize(width: width, height: 48))
            codeLabel.frame.size.width = width - 57
            nameLabel.frame.size.width = width - 57
        }
        if let lastPointer, let screen = screen(at: lastPointer) {
            positionPreview(at: lastPointer, on: screen)
        }
    }

    @objc private func closePressed() { dismiss() }

    /// Exercise actual active-session cursor maintenance after repeated AppKit
    /// resets, then verify dismissal releases the cursor again.
    func checkCursorRestoration() async throws -> Bool {
        try await start()
        defer { dismiss() }
        var recoveries = 0
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 350_000_000)
            guard !menuIsTracking, toolbar?.frame.contains(NSEvent.mouseLocation) != true else { continue }
            NSCursor.arrow.set()
            try await Task.sleep(nanoseconds: 80_000_000)
            guard NSCursor.current === PickerCursor.cursor else { return false }
            recoveries += 1
        }
        dismiss()
        try await Task.sleep(nanoseconds: 100_000_000)
        return recoveries >= 3 && NSCursor.current === NSCursor.arrow
    }

    #if DEBUG
    /// Render the actual AppKit views without starting capture or showing overlays.
    /// Used to check compact layouts with every output format.
    func renderDesignPreviews(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        buildToolbar()
        buildPreview()
        func save(_ view: NSView, name: String) throws {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        if let view = toolbar?.contentView { try save(view, name: "format-bar") }
        for candidate in ColorFormat.allCases {
            format = candidate
            updatePreview(with: SampledColor(hex: 0x86656A))
            if let view = preview?.contentView { try save(view, name: "preview-" + candidate.rawValue) }
        }
        format = .cmyk
        updatePreview(with: SampledColor(hex: 0))
        if let view = preview?.contentView { try save(view, name: "preview-black-CMYK") }
        format = .hex
        updatePreview(with: SampledColor(hex: 0xFAFAD2))
        if let view = preview?.contentView { try save(view, name: "preview-long-name") }
        if let tiff = PickerCursor.image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: directory.appendingPathComponent("eyedropper-cursor.png"))
        }
    }
    #endif

    func dismiss() {
        guard isActive else { return }
        isActive = false
        ready = false
        pointerTracker.stop()
        sessionID += 1
        captureTask?.cancel()
        captureTask = nil
        pendingPoint = nil
        lastPointer = nil
        sampler.reset()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        localKeyMonitor = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        menuIsTracking = false
        catchers.forEach { $0.orderOut(nil) }
        catchers.removeAll()
        toolbar?.orderOut(nil)
        preview?.orderOut(nil)
        toolbar = nil
        preview = nil
        swatch = nil
        codeLabel = nil
        nameLabel = nil
        NSCursor.arrow.set()
        onDismiss?()
    }
}
