import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

public struct InputResult: Encodable {
    public let action: String
    public let ok: Bool
    public let detail: String?
    public let target: String?
}

public enum Input {
    // MARK: - Click

    public static func click(_ node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        guard AXBridge.isAccessibilityTrusted() else {
            throw GuiportError(code: "ax_not_trusted", message: "Accessibility permission not granted",
                               hint: "Grant in System Settings → Privacy & Security → Accessibility")
        }
        // Activate target app first so events route correctly.
        if let running = NSRunningApplication(processIdentifier: app.pid) {
            running.activate(options: [])
        }

        if useAXPress {
            guard let element = try AXBridge.locate(in: app, id: node.id) else {
                throw GuiportError(code: "stale_node", message: "could not relocate element id \(node.id)")
            }
            let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
            if err != .success {
                throw GuiportError(code: "ax_press_failed", message: "AXPress failed (\(err.rawValue))")
            }
            return InputResult(action: "click", ok: true, detail: "AXPress", target: node.id)
        }

        guard let bounds = node.bounds else {
            throw GuiportError(code: "no_bounds", message: "element has no bounds; use --press for AXPress")
        }
        let center = CGPoint(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2)
        let mb = parseButton(button)
        for _ in 0..<max(1, count) {
            try postClick(at: center, button: mb)
        }
        return InputResult(action: "click", ok: true, detail: "synthetic at \(Int(center.x)),\(Int(center.y))", target: node.id)
    }

    // MARK: - Type

    // MARK: - Click at raw coordinates

    public static func clickAt(x: Double, y: Double, button: String = "left", count: Int = 1) throws -> InputResult {
        guard AXBridge.isAccessibilityTrusted() else {
            throw GuiportError(code: "ax_not_trusted", message: "Accessibility permission not granted")
        }
        let point = CGPoint(x: x, y: y)
        let mb = parseButton(button)
        for _ in 0..<max(1, count) {
            try postClick(at: point, button: mb)
        }
        return InputResult(action: "click-at", ok: true, detail: "synthetic at \(Int(x)),\(Int(y))", target: nil)
    }

    public static func type(_ text: String, perCharDelayMs: Int) throws -> InputResult {
        guard AXBridge.isAccessibilityTrusted() else {
            throw GuiportError(code: "ax_not_trusted", message: "Accessibility permission not granted")
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw GuiportError(code: "event_source", message: "could not create CGEventSource")
        }
        // Prefer Unicode injection — works for arbitrary text without keymap concerns.
        for ch in text {
            try postUnicode(String(ch), source: source)
            if perCharDelayMs > 0 {
                usleep(useconds_t(perCharDelayMs * 1000))
            }
        }
        return InputResult(action: "type", ok: true, detail: "\(text.count) chars", target: nil)
    }

    // MARK: - Hotkey

    public static func hotkey(_ combo: String) throws -> InputResult {
        guard AXBridge.isAccessibilityTrusted() else {
            throw GuiportError(code: "ax_not_trusted", message: "Accessibility permission not granted")
        }
        let parts = combo.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else {
            throw GuiportError(code: "hotkey_empty", message: "empty combo")
        }
        var flags: CGEventFlags = []
        var keyCode: CGKeyCode? = nil
        for p in parts {
            switch p {
            case "cmd", "command", "meta", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default:
                if let k = KeyMap.virtualKey(forName: p) {
                    keyCode = k
                } else if p.count == 1, let k = KeyMap.virtualKey(forCharacter: p.first!) {
                    keyCode = k
                } else {
                    throw GuiportError(code: "hotkey_unknown_key", message: "unknown key \"\(p)\"")
                }
            }
        }
        guard let kc = keyCode else {
            throw GuiportError(code: "hotkey_no_key", message: "combo needs a non-modifier key")
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw GuiportError(code: "event_source", message: "could not create CGEventSource")
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: kc, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: kc, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return InputResult(action: "hotkey", ok: true, detail: combo, target: nil)
    }

    // MARK: - Helpers

    private enum MouseButton { case left, right, center }

    private static func parseButton(_ s: String) -> MouseButton {
        switch s.lowercased() {
        case "right", "r": return .right
        case "center", "middle", "m": return .center
        default: return .left
        }
    }

    private static func postClick(at point: CGPoint, button: MouseButton) throws {
        let down: CGEventType
        let up: CGEventType
        let mb: CGMouseButton
        switch button {
        case .left:   down = .leftMouseDown;  up = .leftMouseUp;  mb = .left
        case .right:  down = .rightMouseDown; up = .rightMouseUp; mb = .right
        case .center: down = .otherMouseDown; up = .otherMouseUp; mb = .center
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw GuiportError(code: "event_source", message: "could not create CGEventSource")
        }
        let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: mb)
        let d = CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: point, mouseButton: mb)
        let u = CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: point, mouseButton: mb)
        move?.post(tap: .cghidEventTap)
        d?.post(tap: .cghidEventTap)
        u?.post(tap: .cghidEventTap)
    }

    private static func postUnicode(_ s: String, source: CGEventSource) throws {
        // 0 = no virtual key; we inject as Unicode string.
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            throw GuiportError(code: "event_create", message: "could not create keyboard event")
        }
        let utf16 = Array(s.utf16)
        utf16.withUnsafeBufferPointer { ptr in
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: ptr.baseAddress)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: ptr.baseAddress)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

enum KeyMap {
    /// Common named keys -> virtual key code.
    static func virtualKey(forName n: String) -> CGKeyCode? {
        switch n {
        case "return", "enter": return 0x24
        case "tab": return 0x30
        case "space", "spc": return 0x31
        case "delete", "backspace": return 0x33
        case "escape", "esc": return 0x35
        case "left": return 0x7B
        case "right": return 0x7C
        case "down": return 0x7D
        case "up": return 0x7E
        case "home": return 0x73
        case "end": return 0x77
        case "pageup": return 0x74
        case "pagedown": return 0x79
        case "fwddelete", "forwarddelete": return 0x75
        case "f1": return 0x7A
        case "f2": return 0x78
        case "f3": return 0x63
        case "f4": return 0x76
        case "f5": return 0x60
        case "f6": return 0x61
        case "f7": return 0x62
        case "f8": return 0x64
        case "f9": return 0x65
        case "f10": return 0x6D
        case "f11": return 0x67
        case "f12": return 0x6F
        default: return nil
        }
    }

    static func virtualKey(forCharacter c: Character) -> CGKeyCode? {
        // Lowercase ANSI map.
        let map: [Character: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
            "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
        ]
        return map[Character(c.lowercased())]
    }
}
