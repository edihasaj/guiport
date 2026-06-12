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
    public func preparePermissionIdentity() -> String? { PermissionApp.installOrRefresh() }

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

enum PermissionApp {
    static let bundleID = "com.edihasaj.guiport"

    static func installOrRefresh() -> String? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let app = home.appendingPathComponent("Applications/guiport.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let appExecutable = macOS.appendingPathComponent("guiport")
        let appIcon = resources.appendingPathComponent("guiport.icns")
        let plist = contents.appendingPathComponent("Info.plist")

        do {
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            if fm.fileExists(atPath: appExecutable.path) {
                try fm.removeItem(at: appExecutable)
            }
            try fm.copyItem(at: executable, to: appExecutable)
            if let icon = findIcon(), fm.fileExists(atPath: icon.path) {
                if fm.fileExists(atPath: appIcon.path) {
                    try fm.removeItem(at: appIcon)
                }
                try fm.copyItem(at: icon, to: appIcon)
            }
            try writeInfoPlist(to: plist)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appExecutable.path)
            _ = run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", bundleID, appExecutable.path])
            _ = run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", bundleID, app.path])
            _ = run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", app.path])
            return app.path
        } catch {
            return nil
        }
    }

    private static func writeInfoPlist(to url: URL) throws {
        let version = Guiport.version
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleName</key><string>guiport</string>
          <key>CFBundleDisplayName</key><string>guiport</string>
          <key>CFBundleIdentifier</key><string>\(bundleID)</string>
          <key>CFBundleExecutable</key><string>guiport</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleVersion</key><string>\(version)</string>
          <key>CFBundleShortVersionString</key><string>\(version)</string>
          <key>CFBundleIconFile</key><string>guiport</string>
          <key>LSMinimumSystemVersion</key><string>13.0</string>
          <key>LSUIElement</key><true/>
          <key>NSAccessibilityUsageDescription</key><string>guiport reads the macOS Accessibility tree of running apps so coding agents can inspect UI structure, click by selector, and replay tests deterministically.</string>
          <key>NSScreenCaptureUsageDescription</key><string>guiport captures app windows for screenshots and on-device OCR fallback when an app's accessibility tree is sparse.</string>
          <key>NSAppleEventsUsageDescription</key><string>guiport may activate target apps before sending input events so clicks and keystrokes route correctly.</string>
        </dict>
        </plist>
        """
        try plist.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func findIcon() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/share/guiport/icon.icns"),
            URL(fileURLWithPath: "/usr/local/share/guiport/icon.icns"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Projects/guiport/assets/icon.icns"),
        ]
        if let executable = Bundle.main.executableURL {
            var cursor = executable.deletingLastPathComponent()
            for _ in 0..<8 {
                candidates.append(cursor.appendingPathComponent("assets/icon.icns"))
                cursor.deleteLastPathComponent()
            }
        }
        return candidates.first { fm.fileExists(atPath: $0.path) }
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
