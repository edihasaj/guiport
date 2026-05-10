#if os(Linux)
import Foundation
import GuiportCore

/// Synthetic input via `xdotool` (X11) or `ydotool` (Wayland). Both are passed
/// arguments via discrete argv entries — never through a shell — so titles /
/// type-text are safe even with metacharacters.
///
/// `ydotool` requires the `ydotoold` daemon running with access to `/dev/uinput`.
/// We surface that as a clear error if the daemon socket is missing.
enum LinuxInput {
    static func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult {
        let btn = mouseButton(button)
        switch LinuxSession.current {
        case .x11:
            try Shell.require("xdotool", hint: "Install: sudo apt install xdotool  /  sudo dnf install xdotool")
            let r1 = Shell.env("xdotool", ["mousemove", "\(Int(x))", "\(Int(y))"])
            try check(r1, "xdotool mousemove")
            for _ in 0..<max(1, count) {
                try check(Shell.env("xdotool", ["click", "\(btn)"]), "xdotool click")
            }
        case .wayland:
            try Shell.require("ydotool", hint: "Install ydotool + run ydotoold (needs access to /dev/uinput).")
            try check(Shell.env("ydotool", ["mousemove", "--absolute", "-x", "\(Int(x))", "-y", "\(Int(y))"]),
                      "ydotool mousemove")
            for _ in 0..<max(1, count) {
                try check(Shell.env("ydotool", ["click", "0xC\(btn - 1)"]), "ydotool click")
            }
        case .none:
            throw GuiportError(code: "no_session", message: "no display server (DISPLAY / WAYLAND_DISPLAY unset)")
        }
        return InputResult(action: "click-at", ok: true, detail: "synthetic at \(Int(x)),\(Int(y))", target: nil)
    }

    static func type(_ text: String, perCharDelayMs: Int) throws -> InputResult {
        switch LinuxSession.current {
        case .x11:
            try Shell.require("xdotool", hint: "Install xdotool.")
            var args = ["type", "--clearmodifiers"]
            if perCharDelayMs > 0 {
                args += ["--delay", "\(perCharDelayMs)"]
            }
            args += ["--", text]
            try check(Shell.env("xdotool", args), "xdotool type")
        case .wayland:
            try Shell.require("ydotool", hint: "Install ydotool + run ydotoold.")
            var args = ["type"]
            if perCharDelayMs > 0 {
                args += ["--key-delay", "\(perCharDelayMs)"]
            }
            args += ["--", text]
            try check(Shell.env("ydotool", args), "ydotool type")
        case .none:
            throw GuiportError(code: "no_session", message: "no display server")
        }
        return InputResult(action: "type", ok: true, detail: "\(text.count) chars", target: nil)
    }

    static func hotkey(_ combo: String) throws -> InputResult {
        let normalized = normalize(combo)
        switch LinuxSession.current {
        case .x11:
            try Shell.require("xdotool", hint: "Install xdotool.")
            try check(Shell.env("xdotool", ["key", "--clearmodifiers", normalized]), "xdotool key")
        case .wayland:
            try Shell.require("ydotool", hint: "Install ydotool + run ydotoold.")
            // ydotool's `key` syntax differs (uses raw evdev codes). Easiest
            // portable path: parse combo and synthesize via xdotool-like names
            // through `ydotool key` which accepts `KEY_LEFTCTRL+KEY_S` form.
            let yd = ydotoolForm(normalized)
            try check(Shell.env("ydotool", ["key", yd]), "ydotool key")
        case .none:
            throw GuiportError(code: "no_session", message: "no display server")
        }
        return InputResult(action: "hotkey", ok: true, detail: combo, target: nil)
    }

    // MARK: - Helpers

    /// Convert a guiport-style combo ("cmd+s", "ctrl+shift+t") to xdotool's `+`-separated form
    /// using its key-name vocabulary (Control_L, Shift_L, etc.).
    private static func normalize(_ combo: String) -> String {
        let parts = combo.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        for p in parts {
            switch p {
            case "ctrl", "control":     out.append("ctrl")
            case "shift":               out.append("shift")
            case "alt", "option", "opt": out.append("alt")
            case "cmd", "command", "meta", "win", "super": out.append("super")
            case "enter", "return":     out.append("Return")
            case "tab":                 out.append("Tab")
            case "esc", "escape":       out.append("Escape")
            case "space":               out.append("space")
            case "backspace":           out.append("BackSpace")
            case "delete", "del":       out.append("Delete")
            case "left":                out.append("Left")
            case "right":               out.append("Right")
            case "up":                  out.append("Up")
            case "down":                out.append("Down")
            case "home":                out.append("Home")
            case "end":                 out.append("End")
            case "pageup":              out.append("Page_Up")
            case "pagedown":            out.append("Page_Down")
            default:                    out.append(p)
            }
        }
        return out.joined(separator: "+")
    }

    private static func ydotoolForm(_ xform: String) -> String {
        // ydotool wants KEY_* names joined by `+`. Map the common subset.
        let parts = xform.split(separator: "+").map(String.init)
        let map: [String: String] = [
            "ctrl": "KEY_LEFTCTRL", "shift": "KEY_LEFTSHIFT", "alt": "KEY_LEFTALT", "super": "KEY_LEFTMETA",
            "Return": "KEY_ENTER", "Tab": "KEY_TAB", "Escape": "KEY_ESC", "space": "KEY_SPACE",
            "BackSpace": "KEY_BACKSPACE", "Delete": "KEY_DELETE",
            "Left": "KEY_LEFT", "Right": "KEY_RIGHT", "Up": "KEY_UP", "Down": "KEY_DOWN",
            "Home": "KEY_HOME", "End": "KEY_END", "Page_Up": "KEY_PAGEUP", "Page_Down": "KEY_PAGEDOWN",
        ]
        return parts.map { map[$0] ?? "KEY_\($0.uppercased())" }.joined(separator: "+")
    }

    private static func mouseButton(_ s: String) -> Int {
        switch s.lowercased() {
        case "right":  return 3
        case "middle": return 2
        default:       return 1
        }
    }

    private static func check(_ r: Shell.Result, _ what: String) throws {
        if r.exit != 0 {
            throw GuiportError(
                code: "input_failed",
                message: "\(what) exit \(r.exit): \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))",
                hint: nil
            )
        }
    }
}
#endif
