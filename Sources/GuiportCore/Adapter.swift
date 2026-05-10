import Foundation

/// Permission categories surfaced by the doctor and adapters.
public enum PermissionKind: String, Sendable {
    case accessibility
    case screenRecording
    case inputMonitoring
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

    // MARK: - AX inspection

    func observe(target: AppTarget) throws -> AXSummary
    func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool) throws -> AXNode

    // MARK: - Input

    func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult
    func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult
    func type(text: String, perCharDelayMs: Int) throws -> InputResult
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
    func clickAt(x: Double, y: Double) throws -> InputResult {
        try clickAt(x: x, y: y, button: "left", count: 1)
    }
    func tree(target: AppTarget) throws -> AXNode {
        try tree(target: target, maxDepth: 30, includeHidden: false)
    }
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
    public func openSystemSettings(for permission: PermissionKind) {}
    public func enrolScreenRecording() {}

    public func listApps(onlyWithWindows: Bool) throws -> [AppInfo] { throw unsupported("listing apps") }
    public func resolveApp(name: String?, windowTitle: String?) throws -> AppTarget { throw unsupported("resolving an app") }
    public func windowCount(pid: Int32) -> Int { 0 }

    public func observe(target: AppTarget) throws -> AXSummary { throw unsupported("observe") }
    public func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool) throws -> AXNode { throw unsupported("tree") }

    public func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        throw unsupported("click")
    }
    public func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult { throw unsupported("click-at") }
    public func type(text: String, perCharDelayMs: Int) throws -> InputResult { throw unsupported("type") }
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
