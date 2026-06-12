import Foundation

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
    public static func checkAll() -> DoctorReport {
        let a = Adapter.current
        let checks: [DoctorReport.Check] = [
            checkOS(platform: a.platformName),
            checkAccessibility(adapter: a),
            checkScreenRecording(adapter: a),
        ]
        return DoctorReport(
            ok: checks.allSatisfy(\.ok),
            platform: a.platformName,
            version: Guiport.version,
            checks: checks
        )
    }

    /// Trigger any missing prompts and (best-effort) open System Settings panes.
    /// For Screen Recording, also force an actual capture attempt so macOS reliably
    /// enrols the binary into TCC. After this runs, an entry named `guiport` will
    /// appear under System Settings → Privacy & Security → Screen Recording (if it
    /// wasn't already there).
    public static func fix() -> DoctorReport {
        let a = Adapter.current
        _ = a.preparePermissionIdentity()
        if !a.isAccessibilityTrusted() {
            _ = a.promptAccessibility()
            a.openSystemSettings(for: .accessibility)
        }
        if !a.hasScreenRecordingPermission() {
            _ = a.requestScreenRecordingPermission()
            a.enrolScreenRecording()       // forces TCC enrolment
            a.openSystemSettings(for: .screenRecording)
        }
        return checkAll()
    }

    public static func ensureAccessibilityOrThrow() throws {
        let a = Adapter.current
        if a.isAccessibilityTrusted() { return }
        _ = a.promptAccessibility()
        a.openSystemSettings(for: .accessibility)
        throw GuiportError(
            code: "ax_not_trusted",
            message: "Accessibility permission required",
            hint: "System Settings was opened — toggle guiport ON, then re-run."
        )
    }

    public static func ensureScreenRecordingOrThrow() throws {
        let a = Adapter.current
        if a.hasScreenRecordingPermission() { return }
        _ = a.requestScreenRecordingPermission()
        a.openSystemSettings(for: .screenRecording)
        throw GuiportError(
            code: "screen_recording_not_granted",
            message: "Screen Recording permission required",
            hint: "System Settings was opened — toggle guiport ON, then re-run."
        )
    }

    private static func checkOS(platform: String) -> DoctorReport.Check {
        let v = ProcessInfo.processInfo.operatingSystemVersionString
        return .init(name: "os", ok: true, detail: "\(platform) — \(v)", hint: nil)
    }

    private static func checkAccessibility(adapter: DesktopAdapter) -> DoctorReport.Check {
        let trusted = adapter.isAccessibilityTrusted()
        return .init(
            name: "accessibility",
            ok: trusted,
            detail: trusted ? "trusted" : "not trusted",
            hint: trusted ? nil : "Run `guiport doctor --fix` or grant in System Settings → Privacy & Security → Accessibility"
        )
    }

    private static func checkScreenRecording(adapter: DesktopAdapter) -> DoctorReport.Check {
        let granted = adapter.hasScreenRecordingPermission()
        return .init(
            name: "screen_recording",
            ok: granted,
            detail: granted ? "granted" : "not granted",
            hint: granted ? nil : "Run `guiport doctor --fix` or grant in System Settings → Privacy & Security → Screen Recording"
        )
    }
}
