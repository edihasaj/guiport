import ApplicationServices
import AppKit
import Foundation

public struct Bounds: Encodable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public struct AXNode: Encodable {
    public let id: String
    public let role: String
    public let subrole: String?
    public let name: String?
    public let value: String?
    public let identifier: String?
    public let description: String?
    public let help: String?
    public let bounds: Bounds?
    public let enabled: Bool?
    public let focused: Bool?
    public let selected: Bool?
    public let actions: [String]
    public var children: [AXNode]
}

public struct WindowInfo: Encodable {
    public let title: String?
    public let bounds: Bounds?
}

public struct AXSummary: Encodable {
    public let app: AppInfo
    public let window: WindowInfo?
    public let focusedRole: String?
    public let focusedName: String?
    public let topLevelChildren: Int
}

public enum AXBridge {
    // MARK: - Permissions

    public static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    public static func promptAccessibilityIfNeeded() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - App-level

    public static func windowCount(pid: pid_t) -> Int {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let arr = value as? [AXUIElement] else { return 0 }
        return arr.count
    }

    // MARK: - Observe

    public static func observe(target: AppTarget) throws -> AXSummary {
        try requireTrusted()
        let appElement = AXUIElementCreateApplication(target.pid)
        let appInfo = AppInfo(
            name: target.name,
            bundleId: target.bundleId,
            pid: target.pid,
            active: NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
            windowCount: windowCount(pid: target.pid)
        )

        let window = focusedOrTitledWindow(in: appElement, titleHint: target.windowTitleHint)
        let windowInfo: WindowInfo? = window.flatMap { w in
            WindowInfo(title: stringAttr(w, kAXTitleAttribute as CFString), bounds: bounds(of: w))
        }

        var focusedRole: String?
        var focusedName: String?
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef as! AXUIElement?
        {
            focusedRole = stringAttr(focused, kAXRoleAttribute as CFString)
            focusedName = stringAttr(focused, kAXTitleAttribute as CFString) ?? stringAttr(focused, kAXValueAttribute as CFString)
        }

        var topLevel = 0
        if let w = window {
            var childRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXChildrenAttribute as CFString, &childRef) == .success,
               let arr = childRef as? [AXUIElement] {
                topLevel = arr.count
            }
        }

        return AXSummary(app: appInfo, window: windowInfo, focusedRole: focusedRole, focusedName: focusedName, topLevelChildren: topLevel)
    }

    // MARK: - Tree

    public static func tree(target: AppTarget, maxDepth: Int = 30, includeHidden: Bool = false) throws -> AXNode {
        try requireTrusted()
        let appElement = AXUIElementCreateApplication(target.pid)
        // Coax Chromium/Electron apps into exposing their full AX tree.
        enableElectronAX(appElement)
        let root = focusedOrTitledWindow(in: appElement, titleHint: target.windowTitleHint) ?? appElement
        var pathCounter = PathCounter()
        return walk(root, depth: 0, maxDepth: maxDepth, path: "/", counter: &pathCounter, includeHidden: includeHidden)
    }

    /// Some Electron/Chromium apps gate their full AX tree behind `AXManualAccessibility` /
    /// `AXEnhancedUserInterface`. Setting these attributes is best-effort — non-Chromium apps
    /// will just ignore them.
    private static func enableElectronAX(_ appElement: AXUIElement) {
        let trueRef: CFBoolean = kCFBooleanTrue
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, trueRef)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, trueRef)
    }

    /// Find the AXUIElement matching a stable id from a previous tree walk. O(tree).
    public static func locate(in target: AppTarget, id: String) throws -> AXUIElement? {
        try requireTrusted()
        let appElement = AXUIElementCreateApplication(target.pid)
        let root = focusedOrTitledWindow(in: appElement, titleHint: target.windowTitleHint) ?? appElement
        var counter = PathCounter()
        return walkRaw(root, depth: 0, maxDepth: 60, path: "/", counter: &counter, target: id)
    }

    // MARK: - Internals

    private static func requireTrusted() throws {
        guard AXIsProcessTrusted() else {
            // Fire the system prompt + open Settings on the first try; instructive error otherwise.
            _ = promptAccessibilityIfNeeded()
            #if canImport(AppKit)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                _ = NSWorkspace.shared.open(url)
            }
            #endif
            throw GuiportError(code: "ax_not_trusted",
                               message: "Accessibility permission required",
                               hint: "System Settings was opened — toggle guiport ON, then re-run.")
        }
    }

    private static func focusedOrTitledWindow(in appElement: AXUIElement, titleHint: String?) -> AXUIElement? {
        if let hint = titleHint, !hint.isEmpty {
            var winsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &winsRef) == .success,
               let wins = winsRef as? [AXUIElement] {
                let lc = hint.lowercased()
                if let m = wins.first(where: { (stringAttr($0, kAXTitleAttribute as CFString) ?? "").lowercased().contains(lc) }) {
                    return m
                }
            }
        }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success {
            return ref as! AXUIElement?
        }
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &ref) == .success {
            return ref as! AXUIElement?
        }
        var winsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &winsRef) == .success,
           let wins = winsRef as? [AXUIElement], let first = wins.first {
            return first
        }
        return nil
    }

    private struct PathCounter {
        var counts: [String: Int] = [:]
        mutating func next(parent: String, role: String) -> Int {
            let key = "\(parent)|\(role)"
            let n = counts[key, default: 0]
            counts[key] = n + 1
            return n
        }
    }

    private static func walk(_ element: AXUIElement,
                             depth: Int,
                             maxDepth: Int,
                             path: String,
                             counter: inout PathCounter,
                             includeHidden: Bool) -> AXNode {
        let role = stringAttr(element, kAXRoleAttribute as CFString) ?? "Unknown"
        let subrole = stringAttr(element, kAXSubroleAttribute as CFString)
        let name = stringAttr(element, kAXTitleAttribute as CFString)
        let value = stringAttr(element, kAXValueAttribute as CFString)
        let identifier = stringAttr(element, kAXIdentifierAttribute as CFString)
        let desc = stringAttr(element, kAXDescriptionAttribute as CFString)
        let help = stringAttr(element, kAXHelpAttribute as CFString)
        let b = bounds(of: element)
        let enabled = boolAttr(element, kAXEnabledAttribute as CFString)
        let focused = boolAttr(element, kAXFocusedAttribute as CFString)
        let selected = boolAttr(element, kAXSelectedAttribute as CFString)
        let acts = actions(of: element)

        let n = counter.next(parent: path, role: role)
        let segment = "\(role)[\(n)]"
        let nodePath = path == "/" ? "/\(segment)" : "\(path)/\(segment)"

        var children: [AXNode] = []
        if depth < maxDepth {
            var childRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childRef) == .success,
               let arr = childRef as? [AXUIElement] {
                var childCounter = PathCounter()
                for c in arr {
                    let child = walk(c, depth: depth + 1, maxDepth: maxDepth, path: nodePath, counter: &childCounter, includeHidden: includeHidden)
                    if !includeHidden, child.bounds == nil, child.children.isEmpty, (child.name?.isEmpty ?? true), (child.value?.isEmpty ?? true) {
                        continue
                    }
                    children.append(child)
                }
            }
        }

        return AXNode(
            id: nodePath,
            role: role,
            subrole: subrole,
            name: name,
            value: value,
            identifier: identifier,
            description: desc,
            help: help,
            bounds: b,
            enabled: enabled,
            focused: focused,
            selected: selected,
            actions: acts,
            children: children
        )
    }

    private static func walkRaw(_ element: AXUIElement,
                                depth: Int,
                                maxDepth: Int,
                                path: String,
                                counter: inout PathCounter,
                                target: String) -> AXUIElement? {
        let role = stringAttr(element, kAXRoleAttribute as CFString) ?? "Unknown"
        let n = counter.next(parent: path, role: role)
        let segment = "\(role)[\(n)]"
        let nodePath = path == "/" ? "/\(segment)" : "\(path)/\(segment)"
        if nodePath == target { return element }
        if depth >= maxDepth { return nil }
        var childRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childRef) == .success,
           let arr = childRef as? [AXUIElement] {
            var childCounter = PathCounter()
            for c in arr {
                if let hit = walkRaw(c, depth: depth + 1, maxDepth: maxDepth, path: nodePath, counter: &childCounter, target: target) {
                    return hit
                }
            }
        }
        return nil
    }

    // MARK: - Attribute helpers

    public static func stringAttr(_ element: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
        if let s = ref as? String { return s }
        if let n = ref as? NSNumber { return n.stringValue }
        return nil
    }

    public static func boolAttr(_ element: AXUIElement, _ attr: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
        if let n = ref as? Bool { return n }
        if let n = ref as? NSNumber { return n.boolValue }
        return nil
    }

    public static func bounds(of element: AXUIElement) -> Bounds? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() {
            AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        }
        if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() {
            AXValueGetValue(s as! AXValue, .cgSize, &size)
        }
        return Bounds(x: Double(pos.x), y: Double(pos.y), width: Double(size.width), height: Double(size.height))
    }

    public static func actions(of element: AXUIElement) -> [String] {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(element, &ref) == .success, let arr = ref as? [String] else { return [] }
        return arr
    }
}
