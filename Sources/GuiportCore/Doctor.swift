import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct DoctorReport: Encodable {
    public struct Check: Encodable {
        public let name: String
        public let ok: Bool
        public let detail: String
        public let hint: String?
    }

    public let ok: Bool
    public let platform: String
    public let version: String
    public let checks: [Check]

    public func humanReport() -> String {
        var lines: [String] = []
        lines.append("guiport \(version)  (\(platform))")
        for c in checks {
            let mark = c.ok ? "✓" : "✗"
            lines.append("  \(mark) \(c.name): \(c.detail)")
            if !c.ok, let h = c.hint { lines.append("    → \(h)") }
        }
        lines.append(ok ? "OK" : "NOT READY — fix the failing checks above")
        return lines.joined(separator: "\n")
    }
}

public enum Doctor {
    /// Fires the macOS permission prompt for Accessibility if not yet trusted.
    /// macOS only shows the system dialog the first time; afterwards the user must toggle
    /// the switch manually in System Settings (the process must be re-launched after).
    public static func requestAccessibility() -> Bool {
        return AXBridge.promptAccessibilityIfNeeded()
    }

    public static func requestScreenRecording() -> Bool {
        return Screenshot.requestScreenRecordingPermission()
    }

    /// Best-effort: opens the System Settings pane for the named permission.
    public static func openSystemSettings(for permission: Permission) {
        let url: String
        switch permission {
        case .accessibility:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let u = URL(string: url) {
            #if canImport(AppKit)
            _ = NSWorkspace.shared.open(u)
            #endif
        }
    }

    public enum Permission { case accessibility, screenRecording }

    /// Trigger any missing prompts and (best-effort) open System Settings panes.
    /// Returns the post-fix report.
    public static func fix() -> DoctorReport {
        if !AXBridge.isAccessibilityTrusted() {
            _ = requestAccessibility()
            openSystemSettings(for: .accessibility)
        }
        if !Screenshot.hasScreenRecordingPermission() {
            _ = requestScreenRecording()
            openSystemSettings(for: .screenRecording)
        }
        return checkAll()
    }

    /// Convenience used by commands that need AX. If not trusted, fires the prompt,
    /// opens System Settings, and throws — caller turns it into a friendly CLI exit.
    public static func ensureAccessibilityOrThrow() throws {
        if AXBridge.isAccessibilityTrusted() { return }
        _ = requestAccessibility()
        openSystemSettings(for: .accessibility)
        throw GuiportError(
            code: "ax_not_trusted",
            message: "Accessibility permission required",
            hint: "System Settings was opened — toggle guiport ON, then re-run."
        )
    }

    public static func ensureScreenRecordingOrThrow() throws {
        if Screenshot.hasScreenRecordingPermission() { return }
        _ = requestScreenRecording()
        openSystemSettings(for: .screenRecording)
        throw GuiportError(
            code: "screen_recording_not_granted",
            message: "Screen Recording permission required",
            hint: "System Settings was opened — toggle guiport ON, then re-run."
        )
    }

    public static func checkAll() -> DoctorReport {
        let checks: [DoctorReport.Check] = [
            checkOS(),
            checkAccessibility(),
            checkScreenRecording(),
        ]
        return DoctorReport(
            ok: checks.allSatisfy(\.ok),
            platform: "macOS",
            version: Guiport.version,
            checks: checks
        )
    }

    private static func checkOS() -> DoctorReport.Check {
        let v = ProcessInfo.processInfo.operatingSystemVersionString
        return .init(name: "os", ok: true, detail: v, hint: nil)
    }

    private static func checkAccessibility() -> DoctorReport.Check {
        let trusted = AXBridge.isAccessibilityTrusted()
        return .init(
            name: "accessibility",
            ok: trusted,
            detail: trusted ? "trusted" : "not trusted",
            hint: trusted ? nil : "Grant Accessibility access in System Settings → Privacy & Security → Accessibility"
        )
    }

    private static func checkScreenRecording() -> DoctorReport.Check {
        let granted = Screenshot.hasScreenRecordingPermission()
        return .init(
            name: "screen_recording",
            ok: granted,
            detail: granted ? "granted" : "not granted",
            hint: granted ? nil : "Grant Screen Recording in System Settings → Privacy & Security → Screen Recording"
        )
    }
}
