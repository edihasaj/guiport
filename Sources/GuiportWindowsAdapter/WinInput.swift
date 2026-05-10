#if os(Windows)
import Foundation
import WinSDK
import GuiportCore

/// Synthetic input via `SendInput`. UIPI rules apply: input into elevated
/// targets from a non-elevated guiport process is silently dropped by the OS;
/// we surface that as a clear error after the call returns 0.
enum WinInput {
    static func clickAt(x: Double, y: Double, button: String, count: Int) throws -> InputResult {
        try moveAbsolute(x: x, y: y)
        let (down, up) = mouseFlags(for: button)
        for _ in 0..<max(1, count) {
            try send(mouseFlags: down)
            try send(mouseFlags: up)
        }
        return InputResult(
            action: "click-at",
            ok: true,
            detail: "synthetic at \(Int(x)),\(Int(y))",
            target: nil
        )
    }

    static func type(_ text: String, perCharDelayMs: Int) throws -> InputResult {
        for ch in text.unicodeScalars {
            try sendUnicode(scalar: ch)
            if perCharDelayMs > 0 {
                Sleep(DWORD(perCharDelayMs))
            }
        }
        return InputResult(action: "type", ok: true, detail: "\(text.count) chars", target: nil)
    }

    static func hotkey(_ combo: String) throws -> InputResult {
        let parts = combo.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else {
            throw GuiportError(code: "hotkey_empty", message: "empty combo")
        }
        var modifiers: [WORD] = []
        var key: WORD? = nil
        for p in parts {
            switch p {
            case "ctrl", "control":              modifiers.append(WORD(VK_CONTROL))
            case "shift":                        modifiers.append(WORD(VK_SHIFT))
            case "alt", "option", "opt":         modifiers.append(WORD(VK_MENU))
            case "cmd", "command", "meta", "win": modifiers.append(WORD(VK_LWIN))
            default:
                if let k = vkForKey(p) { key = k }
            }
        }
        guard let key else {
            throw GuiportError(code: "hotkey_no_key", message: "no main key in combo \(combo)")
        }
        // Press modifiers, key down, key up, release modifiers (reverse).
        for m in modifiers { try sendKey(vk: m, down: true) }
        try sendKey(vk: key, down: true)
        try sendKey(vk: key, down: false)
        for m in modifiers.reversed() { try sendKey(vk: m, down: false) }
        return InputResult(action: "hotkey", ok: true, detail: combo, target: nil)
    }

    // MARK: - Mouse

    private static func moveAbsolute(x: Double, y: Double) throws {
        // SendInput with MOUSEEVENTF_ABSOLUTE expects 0..65535 normalized to virtual screen.
        let vx = GetSystemMetrics(SM_XVIRTUALSCREEN)
        let vy = GetSystemMetrics(SM_YVIRTUALSCREEN)
        let vw = GetSystemMetrics(SM_CXVIRTUALSCREEN)
        let vh = GetSystemMetrics(SM_CYVIRTUALSCREEN)
        guard vw > 0, vh > 0 else { return }
        let nx = LONG((x - Double(vx)) * 65535.0 / Double(vw))
        let ny = LONG((y - Double(vy)) * 65535.0 / Double(vh))
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi = MOUSEINPUT(
            dx: nx,
            dy: ny,
            mouseData: 0,
            dwFlags: DWORD(MOUSEEVENTF_MOVE) | DWORD(MOUSEEVENTF_ABSOLUTE) | DWORD(MOUSEEVENTF_VIRTUALDESK),
            time: 0,
            dwExtraInfo: 0
        )
        try sendOne(&input)
    }

    private static func mouseFlags(for button: String) -> (down: DWORD, up: DWORD) {
        switch button.lowercased() {
        case "right":  return (DWORD(MOUSEEVENTF_RIGHTDOWN),  DWORD(MOUSEEVENTF_RIGHTUP))
        case "middle": return (DWORD(MOUSEEVENTF_MIDDLEDOWN), DWORD(MOUSEEVENTF_MIDDLEUP))
        default:       return (DWORD(MOUSEEVENTF_LEFTDOWN),   DWORD(MOUSEEVENTF_LEFTUP))
        }
    }

    private static func send(mouseFlags: DWORD) throws {
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi = MOUSEINPUT(dx: 0, dy: 0, mouseData: 0, dwFlags: mouseFlags, time: 0, dwExtraInfo: 0)
        try sendOne(&input)
    }

    // MARK: - Keyboard

    private static func sendKey(vk: WORD, down: Bool) throws {
        var input = INPUT()
        input.type = DWORD(INPUT_KEYBOARD)
        input.ki = KEYBDINPUT(
            wVk: vk,
            wScan: 0,
            dwFlags: down ? 0 : DWORD(KEYEVENTF_KEYUP),
            time: 0,
            dwExtraInfo: 0
        )
        try sendOne(&input)
    }

    /// Inject a single Unicode scalar via KEYEVENTF_UNICODE. Avoids keymap concerns —
    /// works for any character including emoji on supported targets.
    private static func sendUnicode(scalar: Unicode.Scalar) throws {
        // BMP: one INPUT pair. Above-BMP: surrogate pair, two INPUT pairs.
        let v = scalar.value
        if v <= 0xFFFF {
            try sendUnicodeUnit(WORD(v))
        } else {
            let adjusted = v - 0x10000
            let high: UInt32 = 0xD800 + (adjusted >> 10)
            let low: UInt32  = 0xDC00 + (adjusted & 0x3FF)
            try sendUnicodeUnit(WORD(high))
            try sendUnicodeUnit(WORD(low))
        }
    }

    private static func sendUnicodeUnit(_ unit: WORD) throws {
        var down = INPUT()
        down.type = DWORD(INPUT_KEYBOARD)
        down.ki = KEYBDINPUT(wVk: 0, wScan: unit, dwFlags: DWORD(KEYEVENTF_UNICODE), time: 0, dwExtraInfo: 0)
        try sendOne(&down)
        var up = INPUT()
        up.type = DWORD(INPUT_KEYBOARD)
        up.ki = KEYBDINPUT(
            wVk: 0,
            wScan: unit,
            dwFlags: DWORD(KEYEVENTF_UNICODE) | DWORD(KEYEVENTF_KEYUP),
            time: 0,
            dwExtraInfo: 0
        )
        try sendOne(&up)
    }

    private static func sendOne(_ input: inout INPUT) throws {
        let n = SendInput(1, &input, Int32(MemoryLayout<INPUT>.size))
        if n != 1 {
            throw GuiportError(
                code: "send_input_failed",
                message: "SendInput injected \(n) of 1 events",
                hint: "If the target window is elevated, run guiport elevated too (UIPI)."
            )
        }
    }

    // MARK: - Key map

    /// Single chars + a small set of named keys. Mirrors the macOS adapter's map.
    private static func vkForKey(_ s: String) -> WORD? {
        if s.count == 1, let scalar = s.unicodeScalars.first {
            // VkKeyScanW handles letters/digits/punct in the active layout.
            let vk = VkKeyScanW(WCHAR(scalar.value))
            if vk != -1 { return WORD(vk & 0xFF) }
        }
        switch s {
        case "enter", "return": return WORD(VK_RETURN)
        case "tab":             return WORD(VK_TAB)
        case "esc", "escape":   return WORD(VK_ESCAPE)
        case "space":           return WORD(VK_SPACE)
        case "backspace", "delete": return WORD(VK_BACK)
        case "fwddelete", "del": return WORD(VK_DELETE)
        case "left":   return WORD(VK_LEFT)
        case "right":  return WORD(VK_RIGHT)
        case "up":     return WORD(VK_UP)
        case "down":   return WORD(VK_DOWN)
        case "home":   return WORD(VK_HOME)
        case "end":    return WORD(VK_END)
        case "pageup":   return WORD(VK_PRIOR)
        case "pagedown": return WORD(VK_NEXT)
        case "f1":  return WORD(VK_F1)
        case "f2":  return WORD(VK_F2)
        case "f3":  return WORD(VK_F3)
        case "f4":  return WORD(VK_F4)
        case "f5":  return WORD(VK_F5)
        case "f6":  return WORD(VK_F6)
        case "f7":  return WORD(VK_F7)
        case "f8":  return WORD(VK_F8)
        case "f9":  return WORD(VK_F9)
        case "f10": return WORD(VK_F10)
        case "f11": return WORD(VK_F11)
        case "f12": return WORD(VK_F12)
        default: return nil
        }
    }
}
#endif
