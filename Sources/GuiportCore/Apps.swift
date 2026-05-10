import AppKit
import Foundation

public struct AppInfo: Encodable {
    public let name: String
    public let bundleId: String?
    public let pid: Int32?
    public let active: Bool
    public let windowCount: Int
}

public struct AppTarget {
    public let name: String
    public let bundleId: String?
    public let pid: pid_t
    public let windowTitleHint: String?

    public init(name: String, bundleId: String?, pid: pid_t, windowTitleHint: String? = nil) {
        self.name = name
        self.bundleId = bundleId
        self.pid = pid
        self.windowTitleHint = windowTitleHint
    }
}

public enum AppRegistry {
    /// List running apps with windows. `onlyWithWindows` filters out background apps.
    public static func list(onlyWithWindows: Bool = false) throws -> [AppInfo] {
        let workspace = NSWorkspace.shared
        var infos: [AppInfo] = []
        for running in workspace.runningApplications {
            guard running.activationPolicy != .prohibited else { continue }
            let pid = running.processIdentifier
            let count = AXBridge.windowCount(pid: pid)
            if onlyWithWindows, count == 0 { continue }
            infos.append(AppInfo(
                name: running.localizedName ?? running.bundleIdentifier ?? "pid:\(pid)",
                bundleId: running.bundleIdentifier,
                pid: pid,
                active: running.isActive,
                windowCount: count
            ))
        }
        return infos.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Resolve an app target. If `name` is nil, uses the frontmost app.
    public static func resolve(name: String?, windowTitle: String? = nil) throws -> AppTarget {
        let running = NSWorkspace.shared.runningApplications
        if let name {
            let lc = name.lowercased()
            // Match the same filter as `apps list` so resolve never finds an app the list omits.
            let candidates = running.filter { $0.activationPolicy != .prohibited }
            let exactBundle = candidates.first { $0.bundleIdentifier?.lowercased() == lc }
            let exactName = candidates.first { ($0.localizedName ?? "").lowercased() == lc }
            let substring = candidates.first { ($0.localizedName ?? "").lowercased().contains(lc) }
            let anyMatch = exactBundle ?? exactName ?? substring
                ?? running.first { $0.activationPolicy != .prohibited && (($0.localizedName ?? "").lowercased().contains(lc) || ($0.bundleIdentifier ?? "").lowercased().contains(lc)) }
            guard let m = anyMatch else {
                throw GuiportError(code: "app_not_found", message: "no running app matches \"\(name)\"", hint: "use `guiport apps` to list")
            }
            return AppTarget(name: m.localizedName ?? name, bundleId: m.bundleIdentifier, pid: m.processIdentifier, windowTitleHint: windowTitle)
        } else {
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                throw GuiportError(code: "no_frontmost", message: "no frontmost app", hint: "specify --app")
            }
            return AppTarget(
                name: frontmost.localizedName ?? "frontmost",
                bundleId: frontmost.bundleIdentifier,
                pid: frontmost.processIdentifier,
                windowTitleHint: windowTitle
            )
        }
    }
}
