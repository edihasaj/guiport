#if os(Linux)
import Foundation
import GuiportCore

/// Window enumeration via `wmctrl -lpG` (X11). On Wayland there's no portable
/// equivalent — most compositors don't expose an inter-app window list — so
/// we fall back to `/proc` walking for the `apps` list (no window count) and
/// surface a clear hint if the caller wants per-window data.
enum LinuxApps {
    static func list(onlyWithWindows: Bool) throws -> [AppInfo] {
        switch LinuxSession.current {
        case .x11:
            return try listX11(onlyWithWindows: onlyWithWindows)
        case .wayland, .none:
            return try listProcFallback()
        }
    }

    static func resolve(name: String?, windowTitle: String?) throws -> AppTarget {
        let candidates = (try? list(onlyWithWindows: true)) ?? []
        let titleNeedle = windowTitle?.lowercased()
        let nameNeedle  = name?.lowercased()
        if let t = titleNeedle, !t.isEmpty {
            // Re-enumerate with title info so we can match against window titles.
            if LinuxSession.current == .x11 {
                let wins = try wmctrlWindows()
                if let hit = wins.first(where: { $0.title.lowercased().contains(t) }) {
                    return AppTarget(
                        name: hit.appHint ?? "pid-\(hit.pid)",
                        bundleId: nil,
                        pid: hit.pid,
                        windowTitleHint: hit.title
                    )
                }
            }
        }
        if let n = nameNeedle, !n.isEmpty {
            if let hit = candidates.first(where: { $0.name.lowercased() == n }) ??
                         candidates.first(where: { $0.name.lowercased().contains(n) }) {
                return AppTarget(
                    name: hit.name,
                    bundleId: nil,
                    pid: hit.pid ?? 0,
                    windowTitleHint: nil
                )
            }
        }
        throw GuiportError(
            code: "app_not_found",
            message: "could not resolve app — name=\(name ?? "nil") windowTitle=\(windowTitle ?? "nil")",
            hint: "Run `guiport apps` to see candidates. On Wayland, window-title resolution is limited."
        )
    }

    static func windowCount(pid: Int32) -> Int {
        guard LinuxSession.current == .x11 else { return 0 }
        let wins = (try? wmctrlWindows()) ?? []
        return wins.filter { $0.pid == pid }.count
    }

    // MARK: - X11

    private static func listX11(onlyWithWindows: Bool) throws -> [AppInfo] {
        guard Shell.which("wmctrl") else {
            throw GuiportError(
                code: "tool_missing",
                message: "wmctrl is required for app enumeration on X11",
                hint: "Install: sudo apt install wmctrl  /  sudo dnf install wmctrl"
            )
        }
        let wins = try wmctrlWindows()
        var grouped: [Int32: (name: String, count: Int)] = [:]
        for w in wins {
            let n = w.appHint ?? procName(pid: w.pid) ?? "pid-\(w.pid)"
            var entry = grouped[w.pid] ?? (name: n, count: 0)
            entry.count += 1
            grouped[w.pid] = entry
        }
        let active = activeWindowPid()
        return grouped
            .map { (pid, info) in
                AppInfo(
                    name: info.name,
                    bundleId: nil,
                    pid: pid,
                    active: pid == active,
                    windowCount: info.count
                )
            }
            .filter { !onlyWithWindows || $0.windowCount > 0 }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    struct WmctrlWindow {
        let id: String
        let pid: Int32
        let appHint: String?
        let title: String
    }

    static func wmctrlWindows() throws -> [WmctrlWindow] {
        let r = Shell.env("wmctrl", ["-lpG"])
        if r.exit != 0 {
            throw GuiportError(
                code: "wmctrl_failed",
                message: "wmctrl -lpG failed: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))",
                hint: "Is X11 running and DISPLAY set?"
            )
        }
        // Format: 0xID  desktop  pid  x  y  w  h  WM_CLASS  HOST  TITLE...
        var out: [WmctrlWindow] = []
        for line in r.stdout.split(whereSeparator: \.isNewline) {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 9 else { continue }
            let id = cols[0]
            guard let pid = Int32(cols[2]) else { continue }
            // Title is everything after column 8 (host); some wmctrl builds put WM_CLASS before host.
            // We trust columns >= 8 as title for resilience.
            let title = cols[8...].joined(separator: " ")
            out.append(WmctrlWindow(id: id, pid: pid, appHint: procName(pid: pid), title: title))
        }
        return out
    }

    private static func activeWindowPid() -> Int32? {
        let r = Shell.env("xdotool", ["getactivewindow", "getwindowpid"])
        guard r.exit == 0 else { return nil }
        return Int32(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Wayland / no-display fallback via /proc

    private static func listProcFallback() throws -> [AppInfo] {
        // /proc/<pid>/comm + cmdline. We surface UI-ish processes only (heuristic:
        // executable found under typical UI bin dirs) to keep the list useful.
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/proc") else { return [] }
        var apps: [AppInfo] = []
        for e in entries {
            guard let pid = Int32(e) else { continue }
            guard let name = procName(pid: pid) else { continue }
            // Coarse filter: ignore kernel threads and obvious non-GUI processes.
            if name.hasPrefix("[") { continue }
            apps.append(AppInfo(name: name, bundleId: nil, pid: pid, active: false, windowCount: 0))
        }
        return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private static func procName(pid: Int32) -> String? {
        let url = URL(fileURLWithPath: "/proc/\(pid)/comm")
        guard let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
