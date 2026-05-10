#if os(Windows)
import Foundation
import WinSDK
import GuiportCore

/// Enumerate top-level windows + their owning processes via Win32. We treat each
/// distinct process with at least one visible top-level window as an "app",
/// keyed by the executable's base filename (e.g. `notepad.exe` → "notepad").
enum WinApps {
    struct Win {
        let hwnd: HWND
        let pid: DWORD
        let title: String
        let visible: Bool
    }

    static func list(onlyWithWindows: Bool) throws -> [AppInfo] {
        let wins = enumerateWindows()
        var grouped: [DWORD: (name: String, count: Int, anyTitle: String?)] = [:]
        for w in wins {
            if onlyWithWindows && (!w.visible || w.title.isEmpty) { continue }
            let name = processBaseName(pid: w.pid) ?? "pid-\(w.pid)"
            var entry = grouped[w.pid] ?? (name: name, count: 0, anyTitle: nil)
            entry.count += 1
            if entry.anyTitle == nil, !w.title.isEmpty { entry.anyTitle = w.title }
            grouped[w.pid] = entry
        }
        let foreground = foregroundPid()
        return grouped
            .map { (pid, info) in
                AppInfo(
                    name: info.name,
                    bundleId: nil,
                    pid: Int32(pid),
                    active: pid == foreground,
                    windowCount: info.count
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func resolve(name: String?, windowTitle: String?) throws -> AppTarget {
        let wins = enumerateWindows().filter { $0.visible }
        if let title = windowTitle?.lowercased(), !title.isEmpty {
            if let hit = wins.first(where: { $0.title.lowercased().contains(title) }) {
                let proc = processBaseName(pid: hit.pid) ?? name ?? "pid-\(hit.pid)"
                return AppTarget(name: proc, bundleId: nil, pid: Int32(hit.pid), windowTitleHint: hit.title)
            }
        }
        if let raw = name?.lowercased(), !raw.isEmpty {
            // Match against process basename (with or without `.exe`) or window title.
            let needle = raw.hasSuffix(".exe") ? raw : raw
            if let hit = wins.first(where: { w in
                let proc = (processBaseName(pid: w.pid) ?? "").lowercased()
                return proc == needle
                    || proc == "\(needle).exe"
                    || proc.hasPrefix(needle)
                    || w.title.lowercased().contains(needle)
            }) {
                let proc = processBaseName(pid: hit.pid) ?? raw
                return AppTarget(name: proc, bundleId: nil, pid: Int32(hit.pid), windowTitleHint: hit.title)
            }
        }
        throw GuiportError(
            code: "app_not_found",
            message: "could not resolve app — name=\(name ?? "nil") windowTitle=\(windowTitle ?? "nil")",
            hint: "Run `guiport apps` to see candidates."
        )
    }

    static func windowCount(pid: Int32) -> Int {
        enumerateWindows().filter { $0.pid == DWORD(pid) && $0.visible }.count
    }

    // MARK: - Win32

    private static func enumerateWindows() -> [Win] {
        var out: [Win] = []
        let ctx = WinEnumContext(out: { out.append($0) })
        let opaque = Unmanaged.passUnretained(ctx).toOpaque()
        _ = EnumWindows({ hwnd, lparam in
            guard let hwnd else { return true }
            let ctx = Unmanaged<WinEnumContext>.fromOpaque(UnsafeRawPointer(bitPattern: UInt(lparam))!).takeUnretainedValue()
            var pid: DWORD = 0
            _ = GetWindowThreadProcessId(hwnd, &pid)
            let visible = IsWindowVisible(hwnd)
            let title = readWindowText(hwnd)
            ctx.out(Win(hwnd: hwnd, pid: pid, title: title, visible: visible))
            return true
        }, LPARAM(Int(bitPattern: opaque)))
        return out
    }

    private static func readWindowText(_ hwnd: HWND) -> String {
        let len = GetWindowTextLengthW(hwnd)
        if len <= 0 { return "" }
        var buf = [WCHAR](repeating: 0, count: Int(len) + 1)
        let got = GetWindowTextW(hwnd, &buf, Int32(buf.count))
        if got <= 0 { return "" }
        return String(decodingCString: buf, as: UTF16.self)
    }

    private static func processBaseName(pid: DWORD) -> String? {
        let handle = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid)
        guard let h = handle else { return nil }
        defer { CloseHandle(h) }
        var buf = [WCHAR](repeating: 0, count: 1024)
        var size = DWORD(buf.count)
        if QueryFullProcessImageNameW(h, 0, &buf, &size), size > 0 {
            let full = String(decodingCString: buf, as: UTF16.self)
            // basename without extension
            let comps = full.split(whereSeparator: { $0 == "\\" || $0 == "/" })
            let last = comps.last.map(String.init) ?? full
            if let dot = last.lastIndex(of: ".") {
                return String(last[..<dot])
            }
            return last
        }
        return nil
    }

    private static func foregroundPid() -> DWORD {
        guard let h = GetForegroundWindow() else { return 0 }
        var pid: DWORD = 0
        _ = GetWindowThreadProcessId(h, &pid)
        return pid
    }
}

/// Box for the `EnumWindows` callback — a Swift closure can't be passed to a C
/// function pointer that captures state, so we tunnel context through `LPARAM`.
private final class WinEnumContext {
    let out: (WinApps.Win) -> Void
    init(out: @escaping (WinApps.Win) -> Void) { self.out = out }
}
#endif
