import AppKit
import Foundation
import GuiportCore

/// macOS desktop adapter — Apple Accessibility (AX), CGEvent input, ScreenCaptureKit/CoreGraphics
/// capture, Vision OCR. Install at startup with `Adapter.install(MacAdapter())`.
public struct MacAdapter: DesktopAdapter {
    public init() {}

    public var platformName: String { "macOS" }

    // MARK: - Permissions

    public func isAccessibilityTrusted() -> Bool { AXBridge.isAccessibilityTrusted() }
    public func promptAccessibility() -> Bool { AXBridge.promptAccessibilityIfNeeded() }
    public func hasScreenRecordingPermission() -> Bool { Screenshot.hasScreenRecordingPermission() }
    public func requestScreenRecordingPermission() -> Bool { Screenshot.requestScreenRecordingPermission() }
    public func openSystemSettings(for permission: PermissionKind) {
        let url: String?
        switch permission {
        case .accessibility:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .inputMonitoring:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
        if let s = url, let u = URL(string: s) {
            _ = NSWorkspace.shared.open(u)
        }
    }

    // MARK: - Apps

    public func listApps(onlyWithWindows: Bool) throws -> [AppInfo] {
        try AppRegistry.list(onlyWithWindows: onlyWithWindows)
    }

    public func resolveApp(name: String?, windowTitle: String?) throws -> AppTarget {
        try AppRegistry.resolve(name: name, windowTitle: windowTitle)
    }

    public func windowCount(pid: Int32) -> Int { AXBridge.windowCount(pid: pid) }

    // MARK: - AX inspection

    public func observe(target: AppTarget) throws -> AXSummary {
        try AXBridge.observe(target: target)
    }

    public func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool) throws -> AXNode {
        try AXBridge.tree(target: target, maxDepth: maxDepth, includeHidden: includeHidden)
    }

    // MARK: - Input

    public func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        try Input.click(node, app: app, button: button, count: count, useAXPress: useAXPress)
    }

    public func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult {
        try Input.clickAt(x: x, y: y, button: button, count: count)
    }

    public func type(text: String, perCharDelayMs: Int) throws -> InputResult {
        try Input.type(text, perCharDelayMs: perCharDelayMs)
    }

    public func hotkey(combo: String) throws -> InputResult {
        try Input.hotkey(combo)
    }

    // MARK: - Capture / OCR

    public func captureScreenshot(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        try Screenshot.capture(target: target, to: path)
    }

    public func defaultScreenshotPath() -> String { Screenshot.defaultPath() }

    public func findText(in target: AppTarget?, query: String, exact: Bool, limit: Int) throws -> [OCRMatch] {
        try OCR.findText(in: target, query: query, exact: exact, limit: limit)
    }

    // MARK: - Recorder

    public func startRecording(target: AppTarget, to path: String) throws {
        try Recorder.record(target: target, to: path)
    }
}
