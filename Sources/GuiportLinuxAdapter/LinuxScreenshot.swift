#if os(Linux)
import Foundation
import GuiportCore

/// Capture via the first available tool, in priority order:
///   X11:     scrot → import (ImageMagick) → gnome-screenshot
///   Wayland: grim → gnome-screenshot
/// Per-window capture uses `xdotool getwindowgeometry` on X11 to get bounds and
/// then crops via `import -window <id>` directly (the only tool here that supports
/// per-window targeting). On Wayland per-window capture isn't portable — most
/// compositors gate it behind xdg-desktop-portal — so we surface a clear error.
enum LinuxScreenshot {
    static func capture(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        try ensureParentDir(path)
        switch LinuxSession.current {
        case .x11:     return try captureX11(target: target, to: path)
        case .wayland: return try captureWayland(target: target, to: path)
        case .none:
            throw GuiportError(code: "no_session", message: "no display server (DISPLAY / WAYLAND_DISPLAY unset)")
        }
    }

    // MARK: - X11

    private static func captureX11(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        if let target {
            return try captureX11Window(target: target, to: path)
        }
        if Shell.which("scrot") {
            try check(Shell.env("scrot", ["-o", path]), "scrot")
            return result(path: path, scope: "screen")
        }
        if Shell.which("import") {
            try check(Shell.env("import", ["-window", "root", path]), "import")
            return result(path: path, scope: "screen")
        }
        if Shell.which("gnome-screenshot") {
            try check(Shell.env("gnome-screenshot", ["-f", path]), "gnome-screenshot")
            return result(path: path, scope: "screen")
        }
        throw missingTool(["scrot", "imagemagick (import)", "gnome-screenshot"])
    }

    private static func captureX11Window(target: AppTarget, to path: String) throws -> ScreenshotResult {
        guard Shell.which("import") else {
            throw GuiportError(
                code: "tool_missing",
                message: "per-window capture on X11 requires ImageMagick (`import`)",
                hint: "Install: sudo apt install imagemagick  /  sudo dnf install ImageMagick"
            )
        }
        // Resolve a window id for the pid via wmctrl.
        let wins = (try? LinuxApps.wmctrlWindows()) ?? []
        guard let win = wins.first(where: { $0.pid == target.pid }) else {
            throw GuiportError(code: "no_window", message: "no X11 window for pid \(target.pid)")
        }
        try check(Shell.env("import", ["-window", win.id, path]), "import -window")
        return result(path: path, scope: "window")
    }

    // MARK: - X11 window region (with overlays)

    struct Geometry { let x: Int; let y: Int; let width: Int; let height: Int }

    /// Screen rectangle of the target's first X11 window, via xdotool.
    static func x11Geometry(for target: AppTarget) throws -> Geometry {
        guard LinuxSession.current == .x11 else {
            throw GuiportError(code: "wayland_per_window_unsupported",
                               message: "window regions aren't portable on Wayland",
                               hint: "Omit --app to capture the whole screen.")
        }
        try Shell.require("xdotool", hint: "Install: sudo apt install xdotool")
        let search = Shell.env("xdotool", ["search", "--onlyvisible", "--pid", String(target.pid)])
        guard let id = search.stdout.split(separator: "\n").first.map(String.init) else {
            throw GuiportError(code: "no_window", message: "no X11 window for pid \(target.pid)")
        }
        var values: [String: Int] = [:]
        for line in Shell.env("xdotool", ["getwindowgeometry", "--shell", id]).stdout.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2, let v = Int(parts[1]) { values[String(parts[0])] = v }
        }
        guard let x = values["X"], let y = values["Y"], let w = values["WIDTH"], let h = values["HEIGHT"], w > 0, h > 0 else {
            throw GuiportError(code: "no_window", message: "could not read X11 geometry for pid \(target.pid)")
        }
        return Geometry(x: x, y: y, width: w, height: h)
    }

    /// Crops the window's rectangle from the root window, so other windows
    /// drawn over it (autocomplete suggestions, popovers) are kept.
    static func captureX11Region(target: AppTarget, to path: String) throws -> ScreenshotResult {
        try ensureParentDir(path)
        let g = try x11Geometry(for: target)
        guard Shell.which("import") else { throw missingTool(["imagemagick (import)"]) }
        try check(Shell.env("import", ["-window", "root", "-crop", "\(g.width)x\(g.height)+\(g.x)+\(g.y)", "+repage", path]),
                  "import -crop")
        return result(path: path, scope: "region")
    }

    // MARK: - Wayland

    private static func captureWayland(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        if target != nil {
            throw GuiportError(
                code: "wayland_per_window_unsupported",
                message: "per-window capture isn't portable on Wayland",
                hint: "Capture full screen and crop, or use xdg-desktop-portal (pending)."
            )
        }
        if Shell.which("grim") {
            try check(Shell.env("grim", [path]), "grim")
            return result(path: path, scope: "screen")
        }
        if Shell.which("gnome-screenshot") {
            try check(Shell.env("gnome-screenshot", ["-f", path]), "gnome-screenshot")
            return result(path: path, scope: "screen")
        }
        throw missingTool(["grim", "gnome-screenshot"])
    }

    // MARK: - Helpers

    private static func result(path: String, scope: String) -> ScreenshotResult {
        let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
        let (w, h) = pngDimensions(data) ?? (0, 0)
        return ScreenshotResult(path: path, width: w, height: h, scope: scope)
    }

    /// Best-effort PNG dimension probe — reads the IHDR chunk. Falls back to (0, 0)
    /// for non-PNG output (e.g. user passed a `.jpg` path); the scope/path fields
    /// remain authoritative regardless.
    static func pngDimensions(_ png: Data) -> (Int, Int)? {
        let data = Data(png)  // rebase: slices keep their parent's indices
        guard data.count >= 24 else { return nil }
        // PNG signature 89 50 4E 47 0D 0A 1A 0A
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        for i in 0..<8 where data[i] != sig[i] { return nil }
        // IHDR width/height at bytes 16..<24, big-endian.
        let w = (Int(data[16]) << 24) | (Int(data[17]) << 16) | (Int(data[18]) << 8) | Int(data[19])
        let h = (Int(data[20]) << 24) | (Int(data[21]) << 16) | (Int(data[22]) << 8) | Int(data[23])
        return (w, h)
    }

    private static func ensureParentDir(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private static func missingTool(_ candidates: [String]) -> GuiportError {
        GuiportError(
            code: "tool_missing",
            message: "no screenshot tool available",
            hint: "Install one of: \(candidates.joined(separator: ", "))"
        )
    }

    private static func check(_ r: Shell.Result, _ what: String) throws {
        if r.exit != 0 {
            throw GuiportError(
                code: "screenshot_failed",
                message: "\(what) exit \(r.exit): \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))",
                hint: nil
            )
        }
    }
}
#endif
