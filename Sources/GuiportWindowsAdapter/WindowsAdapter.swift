#if os(Windows)
import Foundation
import WinSDK
import GuiportCore

/// Windows desktop adapter — Win32 SendInput, GDI BitBlt, EnumWindows.
/// UIA-backed tree/observe/find are stubbed until COM bindings land
/// (tracked under the `windows` label).
public struct WindowsAdapter: DesktopAdapter {
    public init() {}

    public var platformName: String { "Windows" }

    // MARK: - Permissions
    //
    // Windows has no TCC equivalent for SendInput / GDI capture / EnumWindows —
    // they work for any process running in the user's interactive session.
    // UIPI may block input into elevated targets; we surface that at the call
    // site, not here.

    public func isAccessibilityTrusted() -> Bool { true }
    public func promptAccessibility() -> Bool { true }
    public func hasScreenRecordingPermission() -> Bool { true }
    public func requestScreenRecordingPermission() -> Bool { true }
    public func preparePermissionIdentity() -> String? { nil }
    public func enrolScreenRecording() {}
    public func openSystemSettings(for permission: PermissionKind) {}

    // MARK: - Apps

    public func listApps(onlyWithWindows: Bool) throws -> [AppInfo] {
        try WinApps.list(onlyWithWindows: onlyWithWindows)
    }

    public func resolveApp(name: String?, windowTitle: String?) throws -> AppTarget {
        try WinApps.resolve(name: name, windowTitle: windowTitle)
    }

    public func windowCount(pid: Int32) -> Int { WinApps.windowCount(pid: pid) }

    // MARK: - AX inspection (UIA pending)

    public func observe(target: AppTarget) throws -> AXSummary {
        throw uiaPending("observe")
    }

    public func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool, scope: TreeScope) throws -> AXNode {
        throw uiaPending("tree")
    }

    // MARK: - Input

    public func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        // Selector-based click depends on the UIA tree. Until that lands, callers
        // can use `click-at <x> <y>` against a known coordinate or use OCR.
        throw uiaPending("click by selector")
    }

    public func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult {
        try WinInput.clickAt(x: x, y: y, button: button, count: count)
    }

    public func type(text: String, perCharDelayMs: Int, method: TypeMethod) throws -> InputResult {
        // method is macOS-only for now (paste vs keystroke); Windows keystrokes.
        try WinInput.type(text, perCharDelayMs: perCharDelayMs)
    }

    public func hotkey(combo: String) throws -> InputResult {
        try WinInput.hotkey(combo)
    }

    // MARK: - Capture / OCR

    public func captureScreenshot(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        try WinScreenshot.capture(target: target, to: path)
    }

    public func defaultScreenshotPath() -> String {
        "artifacts\\screenshot.png"
    }

    public func findText(in target: AppTarget?, query: String, exact: Bool, limit: Int) throws -> [OCRMatch] {
        // Built-in Windows.Media.Ocr (WinRT) via WinOCR — backs find-text and,
        // through it, click-text. No install needed (OCR engine ships with Windows).
        try WinOCR.findText(in: target, query: query, exact: exact, limit: limit)
    }

    // MARK: - Recorder

    public func startRecording(target: AppTarget, to path: String) throws {
        throw GuiportError(
            code: "recorder_pending",
            message: "record is not yet implemented on Windows",
            hint: "Needs SetWindowsHookEx (WH_MOUSE_LL / WH_KEYBOARD_LL) — tracked on roadmap."
        )
    }

    private func uiaPending(_ what: String) -> GuiportError {
        GuiportError(
            code: "uia_pending",
            message: "\(what) requires the UIA backend, which is not yet implemented on Windows",
            hint: "Day-1 surface: apps, click-at, type, hotkey, screenshot. UIA tree tracked under the `windows` label."
        )
    }
}
#endif
