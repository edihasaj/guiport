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
