#if os(Windows)
import Foundation
import WinSDK
import GuiportCore

/// Windows desktop adapter — Win32 SendInput, GDI BitBlt, EnumWindows, and
/// UI Automation for `observe` / `tree` / `find` / selector `click` (see
/// ``WinUIA``). `record` is still pending.
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

    // MARK: - AX inspection (UI Automation)

    public func observe(target: AppTarget) throws -> AXSummary {
        let apps = (try? WinApps.list(onlyWithWindows: false)) ?? []
        let info = apps.first { $0.pid == target.pid }
            ?? AppInfo(name: target.name, bundleId: target.bundleId, pid: target.pid,
                       active: false, windowCount: WinApps.windowCount(pid: target.pid))
        return try WinUIA.observe(target: target, app: info)
    }

    public func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool, scope: TreeScope) throws -> AXNode {
        // `scope` is a macOS distinction (window vs app element vs the status-bar
        // extras menu). Windows has one story: the top-level window's element.
        try WinUIA.tree(target: target, maxDepth: maxDepth, includeHidden: includeHidden)
    }

    // MARK: - Input

    public func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        // Invoke through UIA when asked: an element can be scrolled out of view,
        // or covered by another window, and still be perfectly invokable.
        if useAXPress, (try? WinUIA.invoke(node: node, target: app)) == true {
            return InputResult(action: "click", ok: true,
                               detail: "invoked \(node.role) via UI Automation",
                               target: node.name)
        }
        guard let b = node.bounds, b.width > 0, b.height > 0 else {
            throw GuiportError(
                code: "no_bounds",
                message: "\(node.role) has no on-screen bounds to click",
                hint: "It may be scrolled out of view. `--press` invokes it through "
                    + "UI Automation instead, which does not need it visible."
            )
        }
        return try WinInput.clickAt(x: b.x + b.width / 2, y: b.y + b.height / 2,
                                    button: button, count: count)
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

}
#endif
