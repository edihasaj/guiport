#if os(macOS)
import AppKit
import QuartzCore
import GuiportCore

/// GuiPort brand palette (mirrors the icon + docs site).
enum OverlayTheme {
    static let navy = NSColor(srgbRed: 0x0B/255, green: 0x12/255, blue: 0x20/255, alpha: 1)
    static let amber = NSColor(srgbRed: 0xF5/255, green: 0xA5/255, blue: 0x24/255, alpha: 1)
    static let amber2 = NSColor(srgbRed: 0xFF/255, green: 0xC8/255, blue: 0x57/255, alpha: 1)
    static let bone = NSColor(srgbRed: 0xE9/255, green: 0xE5/255, blue: 0xD4/255, alpha: 1)
}

/// The on-screen "GuiPort is controlling your screen" indicator, shown Codex-style
/// while guiport drives the machine: an animated amber glow around every screen
/// edge, a halo that tracks the cursor, and a small Stop pill at the top. The
/// user keeps full control of the screen; the overlay only *informs* and offers a
/// one-click / one-key way out.
///
/// Lives in the Aqua agent-daemon process (the only guiport process with a GUI
/// session + a persistent run loop). Other guiport processes ping it over the
/// agent socket; see `SessionBridge.pingActivity`.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private var borderWindows: [NSWindow] = []
    private var cursorWindow: NSWindow?
    private var pill: StopPill?
    private var cursorTimer: Timer?
    private var idleTimer: Timer?
    private var escMonitors: [Any] = []
    private var visible = false

    /// After this long with no activity, guiport is considered idle and the
    /// overlay fades away.
    private let idleTimeout: TimeInterval = 2.5

    private init() {}

    // MARK: - Public API (called from the daemon)

    /// Register that guiport just did (or is about to do) something on screen.
    /// Shows the overlay if hidden and resets the idle fade.
    func noteActivity(kind: String, point: CGPoint?) {
        // If the user just pressed Stop, honour the cool-down: don't re-show.
        if Cancellation.isCancelled() { return }
        buildIfNeeded()
        show()
        resetIdleTimer()
    }

    /// The user asked to stop — from the pill button or the ESC key. Records the
    /// cancel signal (which aborts the next forwarded/local op) and tears the
    /// overlay down with a brief "Stopped" acknowledgement.
    func userRequestedStop(reason: String) {
        Cancellation.requestCancel(reason: reason)
        pill?.showStopped()
        idleTimer?.invalidate()
        // Leave the "Stopped" pill up for a beat, then fade everything out.
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    // MARK: - Build

    private func buildIfNeeded() {
        installEscMonitorsIfNeeded()
        if borderWindows.isEmpty { buildBorderWindows() }
        if cursorWindow == nil { buildCursorWindow() }
        if pill == nil { buildPill() }
    }

    private func overlayLevel() -> NSWindow.Level {
        // Above normal windows and the menu bar, below the screen-saver password.
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
    }

    private func overlayBehavior() -> NSWindow.CollectionBehavior {
        [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    private func buildBorderWindows() {
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = overlayLevel()
            w.collectionBehavior = overlayBehavior()
            w.alphaValue = 0
            let view = GlowBorderView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.contentView = view
            w.setFrame(screen.frame, display: true)
            borderWindows.append(w)
        }
    }

    private func buildCursorWindow() {
        let size: CGFloat = 168
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = overlayLevel()
        w.collectionBehavior = overlayBehavior()
        w.alphaValue = 0
        w.contentView = CursorGlowView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        cursorWindow = w
    }

    private func buildPill() {
        let pill = StopPill { [weak self] in
            self?.userRequestedStop(reason: "Stop button")
        }
        pill.level = overlayLevel()
        pill.collectionBehavior = overlayBehavior()
        positionPill(pill)
        self.pill = pill
    }

    private func positionPill(_ pill: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let size = pill.frame.size
        let x = screen.frame.midX - size.width / 2
        // Just below the top edge / menu bar.
        let y = screen.frame.maxY - size.height - 12
        pill.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Show / hide

    private func show() {
        guard !visible else { return }
        visible = true
        odbg("show borderWindows=\(borderWindows.count) pill=\(pill != nil)")
        for w in borderWindows { w.orderFrontRegardless() }
        cursorWindow?.orderFrontRegardless()
        pill?.reset()
        pill?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            for w in borderWindows { w.animator().alphaValue = 1 }
            cursorWindow?.animator().alphaValue = 1
            pill?.animator().alphaValue = 1
        }
        startCursorTracking()
    }

    private func hide() {
        guard visible else { return }
        visible = false
        stopCursorTracking()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            for w in borderWindows { w.animator().alphaValue = 0 }
            cursorWindow?.animator().alphaValue = 0
            pill?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.visible else { return }
            for w in self.borderWindows { w.orderOut(nil) }
            self.cursorWindow?.orderOut(nil)
            self.pill?.orderOut(nil)
        })
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    // MARK: - Cursor tracking

    private func startCursorTracking() {
        guard cursorTimer == nil else { return }
        updateCursorPosition()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCursorPosition() }
        }
        RunLoop.main.add(t, forMode: .common)
        cursorTimer = t
    }

    private func stopCursorTracking() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    private func updateCursorPosition() {
        guard let w = cursorWindow else { return }
        let p = NSEvent.mouseLocation  // global screen coords, bottom-left origin
        let half = w.frame.size.width / 2
        w.setFrameOrigin(NSPoint(x: p.x - half, y: p.y - half))
    }

    // MARK: - ESC to stop

    private func installEscMonitorsIfNeeded() {
        guard escMonitors.isEmpty else { return }
        // Global: user is working in another app while guiport runs. Observed
        // (not consumed) so the user's own ESC still reaches their app.
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.handleEsc() } }
        }) { escMonitors.append(g) }
        // Local: covers the rare case the pill panel holds focus.
        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.handleEsc() }; return nil }
            return e
        }) { escMonitors.append(l) }
    }

    private func handleEsc() {
        guard visible else { return }
        userRequestedStop(reason: "ESC")
    }
}

// MARK: - Glow border view

/// Draws the pulsing amber edge glow: a blurred halo layer for the bloom plus a
/// crisp amber→gold gradient stroke on top.
private final class GlowBorderView: NSView {
    private let halo = CAShapeLayer()
    private let gradient = CAGradientLayer()
    private let gradientMask = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        halo.fillColor = nil
        halo.strokeColor = OverlayTheme.amber.cgColor
        halo.lineWidth = 10
        halo.shadowColor = OverlayTheme.amber.cgColor
        halo.shadowRadius = 28
        halo.shadowOpacity = 0.9
        halo.shadowOffset = .zero
        halo.masksToBounds = false
        layer?.addSublayer(halo)

        gradient.colors = [OverlayTheme.amber2.cgColor, OverlayTheme.amber.cgColor,
                           OverlayTheme.amber2.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradientMask.fillColor = nil
        gradientMask.strokeColor = NSColor.white.cgColor
        gradientMask.lineWidth = 4
        gradient.mask = gradientMask
        layer?.addSublayer(gradient)

        startPulse()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }
    override func layout() {
        super.layout()
        updatePaths()
    }

    private func updatePaths() {
        let rect = bounds.insetBy(dx: 7, dy: 7)
        let path = CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)
        halo.frame = bounds; halo.path = path
        gradient.frame = bounds
        gradientMask.frame = bounds; gradientMask.path = path
    }

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.55
        pulse.toValue = 1.0
        pulse.duration = 1.4
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: "breathe")
    }
}

// MARK: - Cursor glow view

/// A soft radial amber halo centred on its window; the window follows the cursor.
private final class CursorGlowView: NSView {
    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let c = bounds.width / 2
        let center = CGPoint(x: c, y: bounds.height / 2)
        let colors = [
            OverlayTheme.amber2.withAlphaComponent(0.50).cgColor,
            OverlayTheme.amber.withAlphaComponent(0.24).cgColor,
            OverlayTheme.amber.withAlphaComponent(0.0).cgColor,
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colors, locations: [0, 0.55, 1]) else { return }
        ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: c, options: [])
    }
}

// MARK: - Stop pill

/// A small, non-activating panel: pulsing dot + "GuiPort is controlling your
/// screen" + a Stop button. Clicking Stop (or pressing ESC) halts guiport.
private final class StopPill: NSPanel {
    private let onStop: () -> Void
    private let dot = CALayer()
    private let label = NSTextField(labelWithString: "")
    private let button = NSButton()

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
        let size = NSSize(width: 356, height: 40)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        alphaValue = 0

        let content = PillBackgroundView(frame: NSRect(origin: .zero, size: size))
        contentView = content

        // Pulsing status dot.
        dot.backgroundColor = OverlayTheme.amber.cgColor
        dot.frame = CGRect(x: 16, y: size.height / 2 - 4, width: 8, height: 8)
        dot.cornerRadius = 4
        dot.shadowColor = OverlayTheme.amber.cgColor
        dot.shadowRadius = 5
        dot.shadowOpacity = 0.9
        dot.shadowOffset = .zero
        content.layer?.addSublayer(dot)
        let dotPulse = CABasicAnimation(keyPath: "opacity")
        dotPulse.fromValue = 0.35; dotPulse.toValue = 1.0
        dotPulse.duration = 0.9; dotPulse.autoreverses = true; dotPulse.repeatCount = .infinity
        dot.add(dotPulse, forKey: "blink")

        // Status label.
        label.stringValue = "GuiPort is controlling your screen"
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = OverlayTheme.bone
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.frame = NSRect(x: 34, y: 0, width: 220, height: size.height)
        label.alignment = .left
        label.cell?.usesSingleLineMode = true
        (label.cell as? NSTextFieldCell)?.lineBreakMode = .byTruncatingTail
        content.addSubview(label)

        // Stop button.
        configureButton(size: size)
        content.addSubview(button)
    }

    private func configureButton(size: NSSize) {
        button.title = ""
        button.isBordered = false
        button.wantsLayer = true
        button.bezelStyle = .regularSquare
        button.frame = NSRect(x: size.width - 96, y: 6, width: 80, height: 28)
        button.layer?.backgroundColor = OverlayTheme.amber.cgColor
        button.layer?.cornerRadius = 8
        let title = NSAttributedString(string: "Stop  ⎋", attributes: [
            .foregroundColor: OverlayTheme.navy,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .bold),
        ])
        button.attributedTitle = title
        button.target = self
        button.action = #selector(stopTapped)
        // Fire the instant Stop is pressed — snappier for the user and robust to
        // programmatic clicks (whose down/up can arrive too fast for the default
        // mouse-up tracking loop to register).
        button.cell?.sendAction(on: .leftMouseDown)
    }

    @objc private func stopTapped() { onStop() }

    override var canBecomeKey: Bool { true }

    /// Reset to the live "controlling" appearance after a prior "Stopped" state.
    func reset() {
        label.stringValue = "GuiPort is controlling your screen"
        label.textColor = OverlayTheme.bone
        dot.backgroundColor = OverlayTheme.amber.cgColor
        button.isHidden = false
    }

    /// Acknowledge a Stop press before the overlay fades.
    func showStopped() {
        label.stringValue = "Stopped GuiPort"
        dot.backgroundColor = OverlayTheme.bone.cgColor
        button.isHidden = true
    }
}

/// Rounded navy background with a thin amber border for the pill.
private final class PillBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = OverlayTheme.navy.withAlphaComponent(0.94).cgColor
        layer?.cornerRadius = frameRect.height / 2
        layer?.borderWidth = 1
        layer?.borderColor = OverlayTheme.amber.withAlphaComponent(0.55).cgColor
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { false }
}

// MARK: - Daemon host

/// Runs the AppKit application that hosts the overlay. Blocks forever. MUST be
/// called on the main thread (the daemon does this after moving its socket
/// accept loop onto a background thread).
/// Best-effort stderr debug log, gated on `GUIPORT_OVERLAY_DEBUG=1`.
func odbg(_ msg: String) {
    guard ProcessInfo.processInfo.environment["GUIPORT_OVERLAY_DEBUG"] == "1" else { return }
    FileHandle.standardError.write(Data("[guiport-overlay] \(msg)\n".utf8))
}

/// Hop onto the main thread by scheduling on the main **CFRunLoop** and waking it.
///
/// The daemon runs `NSApplication.run()` on the main thread, which pumps the main
/// CFRunLoop — but because guiport's entry point is an `async` main, the Swift
/// concurrency executor and libdispatch's main-queue drain don't reliably service
/// `DispatchQueue.main.async` / `Task { @MainActor }` blocks while AppKit owns the
/// loop. Scheduling directly on the CFRunLoop that `app.run()` actually pumps
/// sidesteps that entirely.
enum MainThreadDispatch {
    static func async(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
            return
        }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { work() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}

public enum OverlayHost {
    public static func runMain() {
        odbg("runMain mainThread=\(Thread.isMainThread)")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // no Dock icon, no menu bar entry
        _ = OverlayController.shared          // create early so ESC monitors install
        app.run()
    }

    /// Note activity from off the main thread (the socket accept loop).
    public static func noteActivity(kind: String, point: CGPoint?) {
        MainThreadDispatch.async {
            OverlayController.shared.noteActivity(kind: kind, point: point)
        }
    }
}
#endif
