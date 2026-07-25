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
            self?.userRequestedStop(reason: "Stop pressed")
        }
        pill.level = overlayLevel()
        pill.collectionBehavior = overlayBehavior()
        positionPill(pill)
        self.pill = pill
    }

    private func positionPill(_ pill: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let size = pill.frame.size
        // Sit just *below* the menu bar (visibleFrame excludes it) so the chip
        // never covers the menu bar, and keep it small so it barely grazes the
        // window title / tab strip underneath.
        let vf = screen.visibleFrame
        let x = vf.midX - size.width / 2
        let y = vf.maxY - size.height - 6
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

/// A small, non-activating chip that sits just below the menu bar: a pulsing
/// amber dot + "Stop guiport" + an `esc` keycap. Deliberately compact so it
/// barely grazes the window content underneath. Clicking anywhere on the chip
/// (or pressing ESC) halts guiport — the whole chip is the hit target, so it
/// works for a real click and a programmatic one alike.
private final class StopPill: NSPanel {
    private let chip: ChipView

    init(onStop: @escaping () -> Void) {
        let size = NSSize(width: 158, height: 28)
        chip = ChipView(frame: NSRect(origin: .zero, size: size), onStop: onStop)
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
        contentView = chip
    }

    override var canBecomeKey: Bool { true }
    func reset() { chip.reset() }
    func showStopped() { chip.showStopped() }
}

/// The chip's content: rounded navy background, thin amber border, pulsing dot,
/// "Stop guiport" label, and an `esc` keycap. The label + keycap are drawn with
/// computed metrics so everything is precisely vertically centred. Handles its
/// own click.
private final class ChipView: NSView {
    private let onStop: () -> Void
    private let dot = CALayer()
    private var stopped = false

    init(frame frameRect: NSRect, onStop: @escaping () -> Void) {
        self.onStop = onStop
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = OverlayTheme.navy.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = frameRect.height / 2
        layer?.borderWidth = 1
        layer?.borderColor = OverlayTheme.amber.withAlphaComponent(0.6).cgColor
        layer?.masksToBounds = true

        // Pulsing amber status dot, vertically centred.
        dot.backgroundColor = OverlayTheme.amber.cgColor
        dot.frame = CGRect(x: 12, y: frameRect.height / 2 - 3, width: 6, height: 6)
        dot.cornerRadius = 3
        dot.shadowColor = OverlayTheme.amber.cgColor
        dot.shadowRadius = 4; dot.shadowOpacity = 0.9; dot.shadowOffset = .zero
        layer?.addSublayer(dot)
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 0.35; blink.toValue = 1.0
        blink.duration = 0.9; blink.autoreverses = true; blink.repeatCount = .infinity
        dot.add(blink, forKey: "blink")
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { false }

    // Whole chip is the Stop control — fire on mouse-down so it's snappy and
    // works for programmatic clicks whose down/up arrive too fast for tracking.
    override func mouseDown(with event: NSEvent) { onStop() }

    func reset() { stopped = false; dot.backgroundColor = OverlayTheme.amber.cgColor; needsDisplay = true }
    func showStopped() { stopped = true; dot.backgroundColor = OverlayTheme.bone.cgColor; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // Label — vertically centred by its own text metrics.
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let label = NSAttributedString(string: stopped ? "Stopped" : "Stop guiport",
                                       attributes: [.font: font, .foregroundColor: OverlayTheme.bone])
        let ls = label.size()
        label.draw(at: CGPoint(x: 26, y: (bounds.height - ls.height) / 2))

        guard !stopped else { return }

        // `esc` keycap — box centred vertically, text centred inside the box.
        let capW: CGFloat = 30, capH: CGFloat = 16
        let cap = NSRect(x: bounds.width - capW - 12, y: (bounds.height - capH) / 2, width: capW, height: capH)
        let box = NSBezierPath(roundedRect: cap, xRadius: 5, yRadius: 5)
        box.lineWidth = 1
        OverlayTheme.amber.withAlphaComponent(0.7).setStroke()
        box.stroke()
        let capText = NSAttributedString(string: "esc", attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: OverlayTheme.amber2,
        ])
        let cs = capText.size()
        capText.draw(at: CGPoint(x: cap.midX - cs.width / 2, y: cap.midY - cs.height / 2))
    }
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
    public static func runMain(autospawn: Bool = false) {
        odbg("runMain mainThread=\(Thread.isMainThread) autospawn=\(autospawn)")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // no Dock icon, no menu bar entry
        _ = OverlayController.shared          // create early so ESC monitors install
        // An auto-spawned daemon (no LaunchAgent) idle-exits so it never lingers
        // as a background process — it only lives while guiport is driving.
        if autospawn {
            let ms = Int(ProcessInfo.processInfo.environment["GUIPORT_DAEMON_IDLE_MS"] ?? "") ?? 300_000
            // runMain is invoked on the main thread (the daemon guarantees it).
            if ms > 0 { MainActor.assumeIsolated { DaemonIdleExit.shared.start(idle: TimeInterval(ms) / 1000) } }
        }
        app.run()
    }

    /// Note activity from off the main thread (the socket accept loop).
    public static func noteActivity(kind: String, point: CGPoint?) {
        MainThreadDispatch.async {
            DaemonIdleExit.shared.touch()
            OverlayController.shared.noteActivity(kind: kind, point: point)
        }
    }
}

/// Idle-exit for an auto-spawned daemon: quit after `idle` seconds without a
/// single request, so the overlay host never outstays guiport's actual use.
/// Disabled unless `start` is called (LaunchAgent daemons keep running).
@MainActor
final class DaemonIdleExit {
    static let shared = DaemonIdleExit()
    private var timer: Timer?
    private var idle: TimeInterval = 300
    private var enabled = false

    func start(idle: TimeInterval) {
        enabled = true
        self.idle = idle
        touch()
    }

    func touch() {
        guard enabled else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: idle, repeats: false) { _ in
            MainActor.assumeIsolated {
                odbg("idle-exit after \(Int(DaemonIdleExit.shared.idle))s idle")
                exit(0)
            }
        }
    }
}
#endif
