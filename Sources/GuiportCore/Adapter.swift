import Foundation

/// Permission categories surfaced by the doctor and adapters.
public enum PermissionKind: String, Sendable {
    case accessibility
    case screenRecording
    case inputMonitoring
}

/// How `type` puts text on screen.
/// - `auto`: the adapter decides — paste into web/Electron content (where fast
///   per-key synthesis drops characters) and keystroke into native fields.
/// - `keystroke`: synthesize one key event per character.
/// - `paste`: place the text on the clipboard and ⌘V it in one shot, then
///   restore the previous clipboard. Reliable for Electron/WebView apps.
public enum TypeMethod: String, Sendable {
    case auto
    case keystroke
    case paste
}

/// Single contract every desktop adapter implements. Add a Windows or Linux adapter by
/// adopting this in its own target. Core code in this module never imports OS frameworks —
/// it routes everything through `Adapter.current`.
public protocol DesktopAdapter: Sendable {
    var platformName: String { get }

    // MARK: - Permissions

    func isAccessibilityTrusted() -> Bool
    func promptAccessibility() -> Bool
    func hasScreenRecordingPermission() -> Bool
    func requestScreenRecordingPermission() -> Bool
    func preparePermissionIdentity() -> String?
    func openSystemSettings(for permission: PermissionKind)

    /// Force a screen-capture API call so macOS reliably enrols the binary into TCC.
    /// Some macOS versions only add an entry to System Settings → Screen Recording after
    /// an actual capture attempt; `CGRequestScreenCaptureAccess()` alone is not always
    /// enough. Implementations should swallow any result.
    func enrolScreenRecording()

    // MARK: - Apps

    func listApps(onlyWithWindows: Bool) throws -> [AppInfo]
    func resolveApp(name: String?, windowTitle: String?) throws -> AppTarget
    func windowCount(pid: Int32) -> Int

    // MARK: - Activation / focus

    /// Foreground a running app **without relaunching it and without a synthetic
    /// click** (which would move the mouse / risk hitting content). No-op-safe
    /// when already frontmost; throws a clear error when the app isn't running.
    /// macOS raises via `NSRunningApplication.activate`; Windows/Linux map to
    /// `SetForegroundWindow` / a WM raise behind the same verb later.
    func activate(target: AppTarget) throws -> ActivationResult

    /// The app currently in the foreground, or `nil` when the platform can't
    /// report it. Backs frontmost guards and `assert --frontmost`.
    func frontmostApp() -> AppInfo?

    // MARK: - AX inspection

    func observe(target: AppTarget) throws -> AXSummary
    func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool, scope: TreeScope) throws -> AXNode

    /// Return the first node matching `selector`, ideally via an early-exit
    /// walk so deep Chromium/Electron trees don't have to be fully built and
    /// serialized just to resolve one click target. A default implementation
    /// (full tree + match) is provided; adapters override for speed.
    func firstMatch(target: AppTarget, selector: Selector, maxDepth: Int, scope: TreeScope) throws -> AXNode?

    // MARK: - Input

    func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult
    func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult
    func type(text: String, perCharDelayMs: Int, method: TypeMethod) throws -> InputResult
    func hotkey(combo: String) throws -> InputResult

    // MARK: - Capture / OCR

    func captureScreenshot(target: AppTarget?, to path: String) throws -> ScreenshotResult
    func defaultScreenshotPath() -> String
    func findText(in target: AppTarget?, query: String, exact: Bool, limit: Int) throws -> [OCRMatch]

    // MARK: - Recorder

    func startRecording(target: AppTarget, to path: String) throws
}

// Convenience overloads with defaults — Swift protocols can't carry default args directly.
public extension DesktopAdapter {
    func resolveApp(name: String?) throws -> AppTarget {
        try resolveApp(name: name, windowTitle: nil)
    }
    /// Type using the automatic method (paste into web/Electron content, keystroke
    /// otherwise). Callers that don't care about the mechanism use this overload.
    func type(text: String, perCharDelayMs: Int) throws -> InputResult {
        try type(text: text, perCharDelayMs: perCharDelayMs, method: .auto)
    }
    func clickAt(x: Double, y: Double) throws -> InputResult {
        try clickAt(x: x, y: y, button: "left", count: 1)
    }
    /// Default first-match: build the full tree and take the first match.
    /// Adapters with a faster path (e.g. macOS early-exit AX walk) override.
    func firstMatch(target: AppTarget, selector: Selector, maxDepth: Int, scope: TreeScope) throws -> AXNode? {
        let t = try tree(target: target, maxDepth: maxDepth, includeHidden: false, scope: scope)
        return selector.match(t).first
    }
    func tree(target: AppTarget) throws -> AXNode {
        try tree(target: target, maxDepth: 30, includeHidden: false, scope: .auto)
    }
    func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool) throws -> AXNode {
        try tree(target: target, maxDepth: maxDepth, includeHidden: includeHidden, scope: .auto)
    }

    /// Default: no activation on platforms that haven't wired the raise call yet.
    /// The macOS adapter overrides. Keeping it here lets Windows/Linux stay
    /// conformant while their raise verb is on the roadmap.
    func activate(target: AppTarget) throws -> ActivationResult {
        throw GuiportError(
            code: "platform_unsupported",
            message: "activate is not implemented on \(platformName) yet",
            hint: "macOS raises via NSRunningApplication.activate; Windows SetForegroundWindow and Linux WM raise are tracked on the roadmap."
        )
    }

    /// Default: platform can't report the frontmost app. Guards that depend on
    /// this fail closed (refuse to send keys), which is the safe behavior.
    func frontmostApp() -> AppInfo? { nil }
}

/// Shared adapter registry. The executable installs the platform adapter at startup;
/// commands and runner read `Adapter.current`.
public enum Adapter {
    public nonisolated(unsafe) static var current: DesktopAdapter = UnconfiguredAdapter()

    public static func install(_ adapter: DesktopAdapter) {
        current = adapter
    }
}

/// Default placeholder used when no adapter has been registered (e.g. on platforms with
/// no implementation yet). Every method throws a clear error pointing to the roadmap.
public struct UnconfiguredAdapter: DesktopAdapter {
    public init() {}

    public var platformName: String { "unconfigured" }

    private func unsupported(_ what: String) -> GuiportError {
        return GuiportError(
            code: "platform_unsupported",
            message: "\(what) is not supported on this platform yet",
            hint: "macOS adapter is the MVP target. Track Windows/Linux adapters on the roadmap."
        )
    }

    public func isAccessibilityTrusted() -> Bool { false }
    public func promptAccessibility() -> Bool { false }
    public func hasScreenRecordingPermission() -> Bool { false }
    public func requestScreenRecordingPermission() -> Bool { false }
    public func preparePermissionIdentity() -> String? { nil }
    public func openSystemSettings(for permission: PermissionKind) {}
    public func enrolScreenRecording() {}

    public func listApps(onlyWithWindows: Bool) throws -> [AppInfo] { throw unsupported("listing apps") }
    public func resolveApp(name: String?, windowTitle: String?) throws -> AppTarget { throw unsupported("resolving an app") }
    public func windowCount(pid: Int32) -> Int { 0 }

    public func observe(target: AppTarget) throws -> AXSummary { throw unsupported("observe") }
    public func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool, scope: TreeScope) throws -> AXNode { throw unsupported("tree") }

    public func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        throw unsupported("click")
    }
    public func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult { throw unsupported("click-at") }
    public func type(text: String, perCharDelayMs: Int, method: TypeMethod) throws -> InputResult { throw unsupported("type") }
    public func hotkey(combo: String) throws -> InputResult { throw unsupported("hotkey") }

    public func captureScreenshot(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        throw unsupported("screenshot")
    }
    public func defaultScreenshotPath() -> String { "artifacts/screenshot.png" }
    public func findText(in target: AppTarget?, query: String, exact: Bool, limit: Int) throws -> [OCRMatch] {
        throw unsupported("find-text")
    }

    public func startRecording(target: AppTarget, to path: String) throws { throw unsupported("record") }
}
