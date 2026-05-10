import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Live recorder using a CGEventTap. Records left-mouse-down events (resolved to AX selectors)
/// and key events (buffered into `type` steps until a non-printable key flushes).
/// Stop with Ctrl+C; the YAML is written on graceful shutdown.
public enum Recorder {
    public static func record(target: AppTarget, to path: String) throws {
        guard AXBridge.isAccessibilityTrusted() else {
            throw GuiportError(code: "ax_not_trusted",
                               message: "Accessibility permission required",
                               hint: "Grant in System Settings → Privacy & Security → Accessibility")
        }

        let session = RecorderSession(target: target, outputPath: path)
        try session.start()
    }
}

private final class RecorderSession {
    let target: AppTarget
    let outputPath: String
    var steps: [String] = []
    var typeBuffer: String = ""
    var lastEventAt: Date = Date()

    init(target: AppTarget, outputPath: String) {
        self.target = target
        self.outputPath = outputPath
    }

    func start() throws {
        steps.append("- wait: 200")
        FileHandle.standardError.write(Data("recording for \(target.name) — interact with the app, Ctrl+C to stop\n".utf8))

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: userInfo
        ) else {
            throw GuiportError(code: "tap_create_failed",
                               message: "could not create CGEventTap",
                               hint: "Grant Input Monitoring + Accessibility, then retry.")
        }

        let runLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // SIGINT → flush + write YAML + exit.
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler { [weak self] in
            guard let self else { return }
            self.flushBuffer()
            self.writeYAML()
            FileHandle.standardError.write(Data("recording saved → \(self.outputPath)\n".utf8))
            exit(0)
        }
        signalSource.resume()
        signal(SIGINT, SIG_IGN)

        CFRunLoopRun()
    }

    func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .leftMouseDown, .rightMouseDown:
            flushBuffer()
            let loc = event.location
            recordClick(at: loc, button: type == .leftMouseDown ? "left" : "right")
        case .keyDown:
            recordKey(event)
        default:
            break
        }
        lastEventAt = Date()
    }

    private func recordClick(at point: CGPoint, button: String) {
        // Use system-wide AX element-at-position to derive a stable selector.
        let systemElement = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        var raw: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &raw)
        if err == .success { hit = raw }

        guard let element = hit else {
            steps.append("# click at \(Int(point.x)),\(Int(point.y)) (no AX element resolved)")
            return
        }

        let role = AXBridge.stringAttr(element, kAXRoleAttribute as CFString) ?? "AXUnknown"
        let name = AXBridge.stringAttr(element, kAXTitleAttribute as CFString)
        let id = AXBridge.stringAttr(element, kAXIdentifierAttribute as CFString)
        let value = AXBridge.stringAttr(element, kAXValueAttribute as CFString)

        let selector = pickSelector(role: role, name: name, identifier: id, value: value)
        let action = button == "left" ? "click" : "click  # right-click via hotkey or AXShowMenu"
        steps.append("- \(action): '\(selector)'")
    }

    private func pickSelector(role: String, name: String?, identifier: String?, value: String?) -> String {
        if let id = identifier, !id.isEmpty {
            return "\(role)[identifier=\"\(escape(id))\"]"
        }
        if let n = name, !n.isEmpty {
            return "\(role)[name=\"\(escape(n))\"]"
        }
        if let v = value, !v.isEmpty, v.count < 60 {
            return "\(role)[value=\"\(escape(v))\"]"
        }
        return role
    }

    private func recordKey(_ event: CGEvent) {
        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Modifier-bearing events → flush as hotkey, not as text.
        let hasMod = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        if hasMod {
            flushBuffer()
            let combo = describeHotkey(keycode: keycode, flags: flags)
            steps.append("- hotkey: \"\(combo)\"")
            return
        }

        // Special keys flush the buffer with a distinct step.
        if let special = specialName(for: keycode) {
            flushBuffer()
            steps.append("- hotkey: \"\(special)\"")
            return
        }

        // Translate to Unicode via UCKeyTranslate via the event's character.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        if length > 0 {
            let str = String(utf16CodeUnits: chars, count: length)
            typeBuffer.append(str)
        }
    }

    private func describeHotkey(keycode: CGKeyCode, flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskAlternate) { parts.append("opt") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if let s = specialName(for: keycode) {
            parts.append(s)
        } else if let c = ansiChar(for: keycode) {
            parts.append(String(c))
        } else {
            parts.append("key\(keycode)")
        }
        return parts.joined(separator: "+")
    }

    private func specialName(for keycode: CGKeyCode) -> String? {
        switch keycode {
        case 0x24: return "return"
        case 0x30: return "tab"
        case 0x33: return "backspace"
        case 0x35: return "escape"
        case 0x7B: return "left"
        case 0x7C: return "right"
        case 0x7D: return "down"
        case 0x7E: return "up"
        case 0x73: return "home"
        case 0x77: return "end"
        case 0x74: return "pageup"
        case 0x79: return "pagedown"
        default: return nil
        }
    }

    private func ansiChar(for keycode: CGKeyCode) -> Character? {
        let map: [CGKeyCode: Character] = [
            0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x",
            0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y",
            0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
            0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1F: "o", 0x20: "u",
            0x22: "i", 0x23: "p", 0x25: "l", 0x26: "j", 0x28: "k",
            0x2D: "n", 0x2E: "m", 0x2F: ".", 0x32: "`",
        ]
        return map[keycode]
    }

    private func flushBuffer() {
        guard !typeBuffer.isEmpty else { return }
        let escaped = typeBuffer
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        steps.append("- type: \"\(escaped)\"")
        typeBuffer = ""
    }

    private func escape(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func writeYAML() {
        let header = """
        # guiport recording — \(ISO8601DateFormatter().string(from: Date()))
        name: \(target.name) recorded
        app: "\(target.name)"
        timeout_ms: 5000
        steps:
        """
        let body = steps.map { "  \($0)" }.joined(separator: "\n")
        let yaml = "\(header)\n\(body)\n"
        try? yaml.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let session = Unmanaged<RecorderSession>.fromOpaque(userInfo).takeUnretainedValue()
        session.handle(type, event)
    }
    return Unmanaged.passUnretained(event)
}
