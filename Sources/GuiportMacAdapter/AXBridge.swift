import ApplicationServices
import AppKit
import Foundation
import GuiportCore

enum AXBridge {
    // MARK: - Permissions

    static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    static func promptAccessibilityIfNeeded() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - App-level

    static func windowCount(pid: pid_t) -> Int {
        let appElement = AXTraversal.application(pid)
        var count: CFIndex = 0
        let err = AXUIElementGetAttributeValueCount(appElement, kAXWindowsAttribute as CFString, &count)
        return err == .success ? count : 0
    }

    // MARK: - Observe

    static func observe(target: AppTarget) throws -> AXSummary {
        var budget = TraversalBudget<AXElementIdentity>()
        try requireTrusted()
        let appElement = AXTraversal.application(target.pid)
        let appInfo = AppInfo(
            name: target.name,
            bundleId: target.bundleId,
            pid: target.pid,
            active: NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
            windowCount: windowCount(pid: target.pid)
        )

        let window = try focusedOrTitledWindow(in: appElement, titleHint: target.windowTitleHint, budget: &budget)
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
            AXTraversal.prepare(w)
            var count: CFIndex = 0
            if AXUIElementGetAttributeValueCount(w, kAXChildrenAttribute as CFString, &count) == .success {
                topLevel = count
            }
        }

        return AXSummary(app: appInfo, window: windowInfo, focusedRole: focusedRole, focusedName: focusedName, topLevelChildren: topLevel)
    }

    // MARK: - Tree

    static func tree(target: AppTarget, maxDepth: Int = 30, includeHidden: Bool = false, scope: TreeScope = .auto) throws -> AXNode {
        try TraversalBudget<AXElementIdentity>.validateDepth(maxDepth)
        var budget = TraversalBudget<AXElementIdentity>()
        try requireTrusted()
        let appElement = AXTraversal.application(target.pid)
        // Coax Chromium/Electron apps into exposing their full AX tree.
        enableElectronAX(appElement)
        let root = try chooseRoot(appElement: appElement, target: target, scope: scope, budget: &budget)
        var pathCounter = PathCounter()
        return try autoreleasepool {
            try walk(root, depth: 0, maxDepth: maxDepth, path: "/", counter: &pathCounter,
                     includeHidden: includeHidden, budget: &budget)
        }
    }

    /// Early-exit search for the first node matching `selector`. Walks the raw
    /// AX tree depth-first, evaluating the selector as it goes, and returns the
    /// moment it matches — so a click target near the top of a huge
    /// Chromium/Electron tree costs a handful of nodes instead of building and
    /// serializing the whole thing.
    ///
    /// Path ids match `tree()` exactly: the per-parent PathCounter is advanced
    /// for every element (same as `walk`), so a returned `id` is relocatable by
    /// `locate()` for AXPress. Truly-empty nodes (no bounds, name, value,
    /// identifier, or description) are skipped from matching — they can't be a
    /// meaningful click target — but their subtrees are still searched.
    static func findFirst(target: AppTarget, selector: GuiportCore.Selector, maxDepth: Int = 30, scope: TreeScope = .auto) throws -> AXNode? {
        try TraversalBudget<AXElementIdentity>.validateDepth(maxDepth)
        var budget = TraversalBudget<AXElementIdentity>()
        try requireTrusted()
        let appElement = AXTraversal.application(target.pid)
        enableElectronAX(appElement)
        let root = try chooseRoot(appElement: appElement, target: target, scope: scope, budget: &budget)
        var counter = PathCounter()
        var matchOrdinal = 0
        return try autoreleasepool {
            try walkFirst(root, depth: 0, maxDepth: maxDepth, path: "/",
                          counter: &counter, selector: selector,
                          wantIndex: selector.index, matchOrdinal: &matchOrdinal, budget: &budget)
        }
    }

    private static func walkFirst(_ element: AXUIElement,
                                  depth: Int,
                                  maxDepth: Int,
                                  path: String,
                                  counter: inout PathCounter,
                                  selector: GuiportCore.Selector,
                                  wantIndex: Int?,
                                  matchOrdinal: inout Int,
                                  budget: inout TraversalBudget<AXElementIdentity>) throws -> AXNode? {
        let identity = AXElementIdentity(element: element)
        try budget.enter(identity)
        defer { budget.leave(identity) }
        let a = try batchFetch(element, budget: &budget)
        let role = cfStr(a[0]) ?? "Unknown"
        let name = cfStr(a[2])
        let value = cfStr(a[3])
        let identifier = cfStr(a[4])
        let desc = cfStr(a[5])
        let b = cfBounds(pos: a[7], size: a[8])

        let n = counter.next(parent: path, role: role)
        let segment = "\(role)[\(n)]"
        let nodePath = path == "/" ? "/\(segment)" : "\(path)/\(segment)"

        // Skip truly-empty nodes from matching (mirrors tree()'s hidden filter),
        // but still walk into them — a bare container can hold real descendants.
        let isEmpty = b == nil && (name?.isEmpty ?? true) && (value?.isEmpty ?? true)
            && (identifier?.isEmpty ?? true) && (desc?.isEmpty ?? true)
        if !isEmpty {
            let candidate = AXNode(
                id: nodePath, role: role, subrole: cfStr(a[1]), name: name, value: value,
                identifier: identifier, description: desc, help: cfStr(a[6]), bounds: b,
                enabled: cfBool(a[9]), focused: cfBool(a[10]), selected: cfBool(a[11]),
                actions: [], children: [])
            if selector.matchesNode(candidate) {
                if let wi = wantIndex {
                    if matchOrdinal == wi {
                        return AXNode(
                            id: nodePath, role: role, subrole: candidate.subrole, name: name, value: value,
                            identifier: identifier, description: desc, help: candidate.help, bounds: b,
                            enabled: candidate.enabled, focused: candidate.focused, selected: candidate.selected,
                            actions: actions(of: element), children: [])
                    }
                    matchOrdinal += 1
                } else {
                    return AXNode(
                        id: nodePath, role: role, subrole: candidate.subrole, name: name, value: value,
                        identifier: identifier, description: desc, help: candidate.help, bounds: b,
                        enabled: candidate.enabled, focused: candidate.focused, selected: candidate.selected,
                        actions: actions(of: element), children: [])
                }
            }
        }

        if depth < maxDepth {
            var childCounter = PathCounter()
            return try AXTraversal.children(of: element, budget: &budget) { c, budget in
                try walkFirst(c, depth: depth + 1, maxDepth: maxDepth, path: nodePath,
                              counter: &childCounter, selector: selector,
                              wantIndex: wantIndex, matchOrdinal: &matchOrdinal, budget: &budget)
            }
        }
        return nil
    }

    /// Resolve the AX root the caller wants to walk.
    /// - `.window`: the focused/titled window (current default behaviour).
    /// - `.tray`:   the app's menu-bar-extras (NSStatusItem area). Many menu-
    ///              bar-only apps expose nothing on `AXWindows`; their
    ///              status items live behind `AXExtrasMenuBar` and are
    ///              otherwise invisible to AX automation.
    /// - `.app`:    the raw application element (top of the tree).
    /// - `.auto`:   window if one exists, otherwise extras menu bar,
    ///              otherwise the app element.
    private static func chooseRoot(appElement: AXUIElement, target: AppTarget, scope: TreeScope,
                                   budget: inout TraversalBudget<AXElementIdentity>) throws -> AXUIElement {
        switch scope {
        case .window:
            return try focusedOrTitledWindow(in: appElement, titleHint: target.windowTitleHint, budget: &budget) ?? appElement
        case .tray:
            return extrasMenuBar(of: appElement) ?? appElement
        case .app:
            return appElement
        case .auto:
            if let w = try focusedOrTitledWindow(in: appElement, titleHint: target.windowTitleHint, budget: &budget),
               windowCount(pid: target.pid) > 0 {
                return w
            }
            if let extras = extrasMenuBar(of: appElement) {
                return extras
            }
            return appElement
        }
    }

    /// Returns the `AXMenuBar` that hosts the app's NSStatusItems. macOS
    /// 13+ exposes it on the application element as `AXExtrasMenuBar`.
    /// Falls back to nil for apps that don't host status items.
    static func extrasMenuBar(of appElement: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &ref) == .success,
              let bar = ref as! AXUIElement?
        else { return nil }
        return bar
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
    /// Tries the window root first (legacy default), then the extras menu
    /// bar (NSStatusItem area), then the bare app element — so click()
    /// resolves nodes that were enumerated under any scope `tree()` may
    /// have used (window vs `--tray`).
    static func locate(in target: AppTarget, id: String) throws -> AXUIElement? {
        var budget = TraversalBudget<AXElementIdentity>()
        try requireTrusted()
        let appElement = AXTraversal.application(target.pid)
        // Match tree(): coax Chromium/Electron into exposing its AX tree so the
        // path ids we relocate (for AXPress) resolve against the same nodes.
        enableElectronAX(appElement)
        var roots: [AXUIElement] = []
        if let w = try focusedOrTitledWindow(in: appElement, titleHint: target.windowTitleHint, budget: &budget) {
            roots.append(w)
        }
        if let extras = extrasMenuBar(of: appElement) {
            roots.append(extras)
        }
        roots.append(appElement)
        for root in roots {
            var counter = PathCounter()
            if let hit = try walkRaw(root, depth: 0, maxDepth: 60, path: "/", counter: &counter,
                                     target: id, budget: &budget) {
                return hit
            }
        }
        return nil
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

    private static func focusedOrTitledWindow(in appElement: AXUIElement, titleHint: String?,
                                              budget: inout TraversalBudget<AXElementIdentity>) throws -> AXUIElement? {
        if let hint = titleHint, !hint.isEmpty {
            let match: AXUIElement? = try AXTraversal.values(
                of: appElement, attribute: kAXWindowsAttribute as CFString, budget: &budget
            ) { window, budget in
                let identity = AXElementIdentity(element: window)
                try budget.enter(identity)
                defer { budget.leave(identity) }
                let title = stringAttr(window, kAXTitleAttribute as CFString)
                try budget.chargeText(title)
                return (title ?? "").lowercased().contains(hint.lowercased()) ? window : nil
            }
            if let match { return match }
        }
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            try budget.checkTime()
            var ref: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &ref)
            try budget.checkTime()
            if error == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
                return (ref as! AXUIElement)
            }
            if error != .success && error != .noValue && error != .attributeUnsupported {
                try AXTraversal.requireSuccess(error)
            }
        }
        return try AXTraversal.values(of: appElement, attribute: kAXWindowsAttribute as CFString, budget: &budget) { window, _ in
            window
        }
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

    // Scalar attributes fetched in ONE batched IPC round-trip per
    // node via AXUIElementCopyMultipleAttributeValues — vs ~13 separate calls.
    // Order must stay in sync with the indexing in `walk`.
    private static let batchAttrs: CFArray = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXValueAttribute,
        kAXIdentifierAttribute, kAXDescriptionAttribute, kAXHelpAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute,
        kAXFocusedAttribute, kAXSelectedAttribute,
    ] as CFArray

    /// One IPC round-trip for every node attribute we serialize. Missing
    /// attributes arrive as kAXValueAXErrorType placeholders (or kCFNull);
    /// both map to nil. This is the single biggest latency lever for deep
    /// Chromium/Electron trees, where per-attribute IPC dominated.
    private static func batchFetch(_ element: AXUIElement,
                                   budget: inout TraversalBudget<AXElementIdentity>) throws -> [CFTypeRef?] {
        try budget.checkTime()
        AXTraversal.prepare(element)
        let count = CFArrayGetCount(batchAttrs)
        var out = [CFTypeRef?](repeating: nil, count: count)
        var valuesRef: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(
            element, batchAttrs, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef)
        try budget.checkTime()
        if err == .cannotComplete {
            throw GuiportError(code: "ax_timeout", message: "The app did not respond to an accessibility attribute request.")
        }
        try AXTraversal.requireSuccess(err)
        guard err == .success, let values = valuesRef as? [AnyObject], values.count == count else {
            return out
        }
        for (i, v) in values.enumerated() {
            if v is NSNull { continue }
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(v as! AXValue) == .axError {
                var error = AXError.success
                if AXValueGetValue(v as! AXValue, .axError, &error),
                   error == .cannotComplete || error == .apiDisabled || error == .invalidUIElement {
                    try AXTraversal.requireSuccess(error, context: "scalar attribute")
                }
                continue
            }
            out[i] = v as CFTypeRef
            if i < 7 { try budget.chargeText(cfStr(v)) }
        }
        return out
    }

    private static func cfStr(_ v: CFTypeRef?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    private static func cfBool(_ v: CFTypeRef?) -> Bool? {
        guard let v, let n = v as? NSNumber else { return nil }
        return n.boolValue
    }

    private static func cfBounds(pos: CFTypeRef?, size: CFTypeRef?) -> Bounds? {
        guard let p = pos, let s = size,
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var cp = CGPoint.zero
        var cs = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &cp)
        AXValueGetValue(s as! AXValue, .cgSize, &cs)
        return Bounds(x: Double(cp.x), y: Double(cp.y), width: Double(cs.width), height: Double(cs.height))
    }

    private static func walk(_ element: AXUIElement,
                             depth: Int,
                             maxDepth: Int,
                             path: String,
                             counter: inout PathCounter,
                             includeHidden: Bool,
                             budget: inout TraversalBudget<AXElementIdentity>) throws -> AXNode {
        let identity = AXElementIdentity(element: element)
        try budget.enter(identity)
        defer { budget.leave(identity) }
        let a = try batchFetch(element, budget: &budget)
        let role = cfStr(a[0]) ?? "Unknown"
        let subrole = cfStr(a[1])
        let name = cfStr(a[2])
        let value = cfStr(a[3])
        let identifier = cfStr(a[4])
        let desc = cfStr(a[5])
        let help = cfStr(a[6])
        let b = cfBounds(pos: a[7], size: a[8])
        let enabled = cfBool(a[9])
        let focused = cfBool(a[10])
        let selected = cfBool(a[11])
        let acts = actions(of: element)
        try budget.checkTime()

        let n = counter.next(parent: path, role: role)
        let segment = "\(role)[\(n)]"
        let nodePath = path == "/" ? "/\(segment)" : "\(path)/\(segment)"

        var children: [AXNode] = []
        if depth < maxDepth {
            var childCounter = PathCounter()
            let _: Bool? = try AXTraversal.children(of: element, budget: &budget) { c, budget in
                let child = try walk(c, depth: depth + 1, maxDepth: maxDepth, path: nodePath,
                                     counter: &childCounter, includeHidden: includeHidden, budget: &budget)
                if !includeHidden, child.bounds == nil, child.children.isEmpty,
                   (child.name?.isEmpty ?? true), (child.value?.isEmpty ?? true) {
                    return nil
                }
                children.append(child)
                return nil
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
                                target: String,
                                budget: inout TraversalBudget<AXElementIdentity>) throws -> AXUIElement? {
        let identity = AXElementIdentity(element: element)
        try budget.enter(identity)
        defer { budget.leave(identity) }
        let role = stringAttr(element, kAXRoleAttribute as CFString) ?? "Unknown"
        try budget.chargeText(role)
        let n = counter.next(parent: path, role: role)
        let segment = "\(role)[\(n)]"
        let nodePath = path == "/" ? "/\(segment)" : "\(path)/\(segment)"
        if nodePath == target { return element }
        if depth >= maxDepth { return nil }
        var childCounter = PathCounter()
        return try AXTraversal.children(of: element, budget: &budget) { c, budget in
            try walkRaw(c, depth: depth + 1, maxDepth: maxDepth, path: nodePath,
                        counter: &childCounter, target: target, budget: &budget)
        }
    }

}
