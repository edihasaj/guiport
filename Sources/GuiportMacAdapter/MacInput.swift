import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import GuiportCore

enum Input {
    // MARK: - Click

    static func click(_ node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        try Doctor.ensureAccessibilityOrThrow()

        if useAXPress {
            activateIfNeeded(app.pid)
            guard let element = try AXBridge.locate(in: app, id: node.id) else {
                throw GuiportError(code: "stale_node", message: "could not relocate element id \(node.id)")
            }
            let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
            if err != .success {
                throw GuiportError(code: "ax_press_failed", message: "AXPress failed (\(err.rawValue))")
            }
            return InputResult(action: "click", ok: true, detail: "AXPress", target: node.id)
        }

        // Fast path: usable on-screen bounds → synthesize a click at center.
        // emitMouse activates the app and posts the event — directly when this
        // process can reach the screen, or via the Aqua agent daemon otherwise.
        if let bounds = node.bounds, bounds.width > 1, bounds.height > 1 {
            let center = CGPoint(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2)
            let detail = try emitMouse(at: center, button: button, count: count, activatePid: app.pid)
            return InputResult(action: "click", ok: true, detail: detail, target: node.id)
        }

        // No usable bounds — element is collapsed or scrolled out of view.
        // Relocate it, ask its container to scroll it into view, and retry with
        // fresh bounds; fall back to AXPress (which doesn't need coordinates).
        guard let element = try AXBridge.locate(in: app, id: node.id) else {
            throw GuiportError(code: "no_bounds",
                               message: "element has no bounds and could not be relocated",
                               hint: "pass --press to use AXPress, or re-`find` the element")
        }
        // kAXScrollToVisibleAction isn't bridged to Swift; use its raw name.
        AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
        if let fresh = AXBridge.bounds(of: element), fresh.width > 1, fresh.height > 1 {
            let center = CGPoint(x: fresh.x + fresh.width / 2, y: fresh.y + fresh.height / 2)
            let detail = try emitMouse(at: center, button: button, count: count, activatePid: app.pid)
            return InputResult(action: "click", ok: true, detail: "scroll-into-view; \(detail)", target: node.id)
        }
        let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if err == .success {
            return InputResult(action: "click", ok: true, detail: "AXPress (no bounds)", target: node.id)
        }
        throw GuiportError(code: "no_bounds",
                           message: "element has no clickable bounds; AXPress fallback also failed (\(err.rawValue))",
                           hint: "the element may be disabled or not actionable")
    }

    // MARK: - Type

    // MARK: - Click at raw coordinates

    static func clickAt(x: Double, y: Double, button: String = "left", count: Int = 1) throws -> InputResult {
        try Doctor.ensureAccessibilityOrThrow()
        let detail = try emitMouse(at: CGPoint(x: x, y: y), button: button, count: count, activatePid: nil)
        return InputResult(action: "click-at", ok: true, detail: detail, target: nil)
    }

    /// Default per-character delay for the keystroke path. Zero-delay Unicode
    /// injection outruns some apps' input queues and drops characters; a small
    /// floor makes native typing reliable without being noticeably slow.
    private static let defaultKeystrokeDelayMs = 6

    static func type(_ text: String, perCharDelayMs: Int, method: TypeMethod = .auto) throws -> InputResult {
        try Doctor.ensureAccessibilityOrThrow()
        if SessionBridge.shouldForward() {
            // Resolve in the executing (daemon) process, which owns the focus/screen.
            try SessionBridge.send(["op": "type", "text": text,
                                    "delayMs": perCharDelayMs, "method": method.rawValue])
            return InputResult(action: "type", ok: true, detail: "\(text.count) chars (via agent)", target: nil)
        }
        switch resolveMethod(method, text: text) {
        case .paste:
            return try pasteText(text)
        default:
            try keystrokeType(text, perCharDelayMs: perCharDelayMs)
            return InputResult(action: "type", ok: true, detail: "\(text.count) chars", target: nil)
        }
    }

    /// Decide how to inject text when the caller asked for `.auto`. Web/Electron
    /// content (Teams, Slack, VS Code, any Chromium/WebView field) drops fast
    /// synthesized keystrokes, so route it — and any multi-line text — through
    /// the clipboard. Native fields keep the keystroke path.
    private static func resolveMethod(_ requested: TypeMethod, text: String) -> TypeMethod {
        guard requested == .auto else { return requested }
        if text.contains("\n") { return .paste }
        if focusedContextIsWebOrElectron() { return .paste }
        return .keystroke
    }

    /// Bundle ids of common Chromium/WebView/Electron desktop apps whose text
    /// fields drop fast synthesized keystrokes. Detecting the frontmost app is
    /// reliable even when the focused element's AXParent chain is broken (as it
    /// often is in WebView2/Chromium — e.g. Teams).
    private static let knownWebApps: Set<String> = [
        "com.microsoft.teams2", "com.microsoft.teams",       // Teams (WebView2)
        "com.tinyspeck.slackmacgap",                          // Slack
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", // VS Code
        "com.hnc.Discord", "com.discordapp.Discord",          // Discord
        "com.github.GitHubClient",                            // GitHub Desktop
        "notion.id", "md.obsidian", "com.spotify.client",
        "com.figma.Desktop", "com.linear",
    ]

    /// True when text is about to land in web/Electron content — checked three
    /// ways for coverage: the frontmost app's bundle id, an Electron framework
    /// inside its bundle, and finally the focused element's AXWebArea ancestry
    /// (browsers and anything not caught by the first two).
    private static func focusedContextIsWebOrElectron() -> Bool {
        if let app = NSWorkspace.shared.frontmostApplication {
            if let bundleID = app.bundleIdentifier, knownWebApps.contains(bundleID) {
                return true
            }
            if let bundleURL = app.bundleURL {
                let electron = bundleURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
                if FileManager.default.fileExists(atPath: electron.path) { return true }
            }
        }
        return focusedElementIsWebContent()
    }

    private static func keystrokeType(_ text: String, perCharDelayMs: Int) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw GuiportError(code: "event_source", message: "could not create CGEventSource")
        }
        let delayMs = perCharDelayMs > 0 ? perCharDelayMs : defaultKeystrokeDelayMs
        // Prefer Unicode injection — works for arbitrary text without keymap concerns.
        for ch in text {
            try postUnicode(String(ch), source: source)
            usleep(useconds_t(delayMs * 1000))
        }
    }

    /// Put `text` on the clipboard, ⌘V it, then restore the prior clipboard.
    /// One paste event lands whole, so no characters are lost — the reliable
    /// path for Electron/WebView editors.
    private static func pasteText(_ text: String) throws -> InputResult {
        let pb = NSPasteboard.general
        let saved = snapshotPasteboard(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        _ = try hotkey("cmd+v")
        usleep(120_000) // let the app consume the paste before we restore the clipboard
        restorePasteboard(pb, saved)
        return InputResult(action: "type", ok: true, detail: "\(text.count) chars (paste)", target: nil)
    }

    /// True when the system-wide focused element sits inside an `AXWebArea`
    /// (Chromium/Electron/WebView web content). Best-effort — any failure means
    /// "assume native".
    private static func focusedElementIsWebContent() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return false
        }
        var current: AXUIElement? = (focused as! AXUIElement)
        var hops = 0
        while let element = current, hops < 25 {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXWebArea" {
                return true
            }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                return false
            }
            current = (parent as! AXUIElement)
            hops += 1
        }
        return false
    }

    private static func snapshotPasteboard(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let value = item.data(forType: type) { data[type] = value }
            }
            return data
        }
    }

    private static func restorePasteboard(_ pb: NSPasteboard, _ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }

    // MARK: - Hotkey

    static func hotkey(_ combo: String) throws -> InputResult {
        try Doctor.ensureAccessibilityOrThrow()
        if SessionBridge.shouldForward() {
            try SessionBridge.send(["op": "hotkey", "combo": combo])
            return InputResult(action: "hotkey", ok: true, detail: "\(combo) (via agent)", target: nil)
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

    // MARK: - Session-bridged emit

    /// Post a click either directly (when this process can reach the screen) or
    /// by forwarding to the Aqua agent daemon (when it can't). Returns a detail
    /// string for the InputResult. `activatePid`, when set and not already
    /// frontmost, raises that app first so the click lands on it.
    private static func emitMouse(at p: CGPoint, button: String, count: Int, activatePid: Int32?) throws -> String {
        if SessionBridge.shouldForward() {
            try SessionBridge.send([
                "op": "mouse",
                "x": Double(p.x), "y": Double(p.y),
                "button": button, "clickCount": max(1, count),
                "activatePid": Int(activatePid ?? 0),
            ])
            return "via agent at \(Int(p.x)),\(Int(p.y))"
        }
        activateIfNeeded(activatePid)
        try postClick(at: p, button: parseButton(button), clickCount: max(1, count))
        return "synthetic at \(Int(p.x)),\(Int(p.y))"
    }

    /// Raise the target app when it isn't already frontmost, then give the
    /// window a brief beat to come forward so the click lands on it.
    private static func activateIfNeeded(_ pid: Int32?) {
        guard let pid, pid != 0,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != pid,
              let running = NSRunningApplication(processIdentifier: pid) else { return }
        running.activate(options: [])
        usleep(40_000)
    }

    /// Dispatch an op received by the Aqua agent daemon. Runs in the daemon
    /// process (graphic access), where the same Input.* paths post locally.
    static func executeForwardedOp(_ op: [String: Any]) throws {
        switch op["op"] as? String {
        case "mouse":
            let x = (op["x"] as? Double) ?? 0
            let y = (op["y"] as? Double) ?? 0
            let button = (op["button"] as? String) ?? "left"
            let count = (op["clickCount"] as? Int) ?? 1
            let pidRaw = (op["activatePid"] as? Int) ?? 0
            _ = try emitMouse(at: CGPoint(x: x, y: y), button: button, count: count,
                              activatePid: pidRaw == 0 ? nil : Int32(pidRaw))
        case "type":
            let method = TypeMethod(rawValue: (op["method"] as? String) ?? "auto") ?? .auto
            _ = try type((op["text"] as? String) ?? "", perCharDelayMs: (op["delayMs"] as? Int) ?? 0, method: method)
        case "hotkey":
            _ = try hotkey((op["combo"] as? String) ?? "")
        default:
            throw GuiportError(code: "daemon_unknown_op", message: "unknown op \(op["op"] as? String ?? "nil")")
        }
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

    /// Synthesize a click of `clickCount` presses at `point`. Each down/up pair
    /// carries an incrementing `mouseEventClickState` (1, 2, …) — this is what
    /// makes count=2 register as a real double-click rather than two unrelated
    /// single clicks (AppKit/Chromium both key double-click on this field).
    private static func postClick(at point: CGPoint, button: MouseButton, clickCount: Int) throws {
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
        // Move the cursor first so hover state and hit-testing resolve at point.
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: mb)?
            .post(tap: .cghidEventTap)
        for i in 1...max(1, clickCount) {
            let d = CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: point, mouseButton: mb)
            let u = CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: point, mouseButton: mb)
            d?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            u?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            d?.post(tap: .cghidEventTap)
            u?.post(tap: .cghidEventTap)
        }
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
