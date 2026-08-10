import AppKit
import CoreGraphics
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
    public func preparePermissionIdentity() -> String? { PermissionApp.registerCurrentBundle() }

    public func enrolScreenRecording() {
        // Side-effecting: fetch ScreenCaptureKit shareable content so macOS enrols
        // guiport (com.edihasaj.guiport) as its OWN Screen Recording subject and adds
        // it to System Settings → Screen Recording. The legacy CGDisplayCreateImage
        // path attributed the grant to the host terminal instead (and is a no-op on
        // macOS 14+). Result is intentionally discarded.
        ScreenCapture.enrol()
    }

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

    // MARK: - Activation / focus

    public func activate(target: AppTarget) throws -> ActivationResult {
        try Activation.activate(target: target)
    }

    public func frontmostApp() -> AppInfo? { Activation.frontmostApp() }

    // MARK: - AX inspection

    public func observe(target: AppTarget) throws -> AXSummary {
        try AXBridge.observe(target: target)
    }

    public func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool, scope: TreeScope) throws -> AXNode {
        try AXBridge.tree(target: target, maxDepth: maxDepth, includeHidden: includeHidden, scope: scope)
    }

    public func firstMatch(target: AppTarget, selector: GuiportCore.Selector, maxDepth: Int, scope: TreeScope) throws -> AXNode? {
        try AXBridge.findFirst(target: target, selector: selector, maxDepth: maxDepth, scope: scope)
    }

    // MARK: - Input

    public func click(node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        try Input.click(node, app: app, button: button, count: count, useAXPress: useAXPress)
    }

    public func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult {
        try Input.clickAt(x: x, y: y, button: button, count: count)
    }

    public func type(text: String, perCharDelayMs: Int, method: TypeMethod) throws -> InputResult {
        try Input.type(text, perCharDelayMs: perCharDelayMs, method: method)
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

enum PermissionApp {
    static func registerCurrentBundle() -> String? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        var cursor = executable.deletingLastPathComponent()
        while cursor.path != "/" {
            if cursor.pathExtension.lowercased() == "app" {
                _ = run(lsregister, ["-f", cursor.path])
                return cursor.path
            }
            cursor.deleteLastPathComponent()
        }
        // Bare build products have unstable identities. Do not create and
        // ad-hoc-sign another bundle here: that creates duplicate TCC rows.
        return nil
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 1
        }
    }
}
