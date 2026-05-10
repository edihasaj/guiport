#if os(Linux)
import Foundation
import GuiportCore

/// Linux desktop adapter — shell-out to standard tools for the day-1 surface.
///
/// Session-aware: on X11 we prefer `xdotool` + `wmctrl` + `scrot`/`import`.
/// On Wayland we prefer `ydotool` + `grim`. Tools are looked up at call time,
/// not at startup — `doctor` reports what's installed and which session is active.
///
/// AT-SPI2 D-Bus tree (observe / tree / find / click-by-selector) is the
/// natural upgrade path; until those bindings land, those calls throw
/// `atspi_pending` with a clear hint.
public struct LinuxAdapter: DesktopAdapter {
    public init() {}

    public var platformName: String {
        switch LinuxSession.current {
        case .wayland: return "Linux (Wayland)"
        case .x11:     return "Linux (X11)"
        case .none:    return "Linux (no display server)"
        }
    }

    // MARK: - Permissions
    //
    // Linux has no TCC analogue. The "permissions" question collapses to "is
    // there a display server reachable?" which we surface via doctor. These
    // accessors are intentionally permissive so the runner doesn't gate calls.

    public func isAccessibilityTrusted() -> Bool { LinuxSession.current != .none }
    public func promptAccessibility() -> Bool { true }
    public func hasScreenRecordingPermission() -> Bool { LinuxSession.current != .none }
    public func requestScreenRecordingPermission() -> Bool { true }
    public func enrolScreenRecording() {}
    public func openSystemSettings(for permission: PermissionKind) {}

    // MARK: - Apps

    public func listApps(onlyWithWindows: Bool) throws -> [AppInfo] {
        try LinuxApps.list(onlyWithWindows: onlyWithWindows)
    }

    public func resolveApp(name: String?, windowTitle: String?) throws -> AppTarget {
        try LinuxApps.resolve(name: name, windowTitle: windowTitle)
    }

    public func windowCount(pid: Int32) -> Int { LinuxApps.windowCount(pid: pid) }

    // MARK: - AX inspection (AT-SPI2 pending)

    public func observe(target: AppTarget) throws -> AXSummary {
        throw atspiPending("observe")
    }

    public func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool, scope: TreeScope) throws -> AXNode {
        throw atspiPending("tree")
    }

    // MARK: - Input

    public func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        throw atspiPending("click by selector")
    }

    public func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult {
        try LinuxInput.clickAt(x: x, y: y, button: button, count: count)
    }

    public func type(text: String, perCharDelayMs: Int) throws -> InputResult {
        try LinuxInput.type(text, perCharDelayMs: perCharDelayMs)
    }

    public func hotkey(combo: String) throws -> InputResult {
        try LinuxInput.hotkey(combo)
    }

    // MARK: - Capture / OCR

    public func captureScreenshot(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        try LinuxScreenshot.capture(target: target, to: path)
    }

    public func defaultScreenshotPath() -> String { "artifacts/screenshot.png" }

    public func findText(in target: AppTarget?, query: String, exact: Bool, limit: Int) throws -> [OCRMatch] {
        // tesseract is the obvious backend; deferred until the AT-SPI2 tree
        // lands so we have proper coordinate framing for matches.
        throw GuiportError(
            code: "ocr_pending",
            message: "find-text is not yet implemented on Linux",
            hint: "Tracked under the `linux` label — tesseract backend pending."
        )
    }

    // MARK: - Recorder

    public func startRecording(target: AppTarget, to path: String) throws {
        throw GuiportError(
            code: "recorder_pending",
            message: "record is not yet implemented on Linux",
            hint: "Needs evdev (X11) or libei (Wayland) — tracked on roadmap."
        )
    }

    private func atspiPending(_ what: String) -> GuiportError {
        GuiportError(
            code: "atspi_pending",
            message: "\(what) requires the AT-SPI2 backend, which is not yet implemented on Linux",
            hint: "Day-1 surface: apps, click-at, type, hotkey, screenshot. AT-SPI2 tree tracked under the `linux` label."
        )
    }
}

/// Detect display server type once per process. Caches the result —
/// switching sessions mid-run isn't a thing in practice.
enum LinuxSession {
    enum Kind { case x11, wayland, none }

    static let current: Kind = detect()

    private static func detect() -> Kind {
        let env = ProcessInfo.processInfo.environment
        if let w = env["WAYLAND_DISPLAY"], !w.isEmpty { return .wayland }
        if let x = env["DISPLAY"], !x.isEmpty { return .x11 }
        if let t = env["XDG_SESSION_TYPE"]?.lowercased() {
            if t == "wayland" { return .wayland }
            if t == "x11"     { return .x11 }
        }
        return .none
    }
}
#endif
