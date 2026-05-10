import Foundation

public struct SmartClickResult: Encodable {
    public let path: String   // "ax" | "ocr"
    public let selector: String
    public let detail: String?
    public let target: String?
}

/// Tries AX selectors first; on no-match, optionally falls back to OCR using the
/// selector's name/text predicate.
///
/// `Mode.auto` (default) tries OCR only when Screen Recording is granted, so it
/// degrades gracefully on unprivileged setups instead of triggering a permission
/// prompt mid-action. Pass `.strict` to disable OCR entirely, or `.ocr` to force
/// it (which will trigger the SR prompt if needed).
public enum SmartClick {
    public enum Mode: String { case auto, ocr, strict }

    public static func click(selector: String,
                             target: AppTarget,
                             button: String = "left",
                             count: Int = 1,
                             useAXPress: Bool = false,
                             mode: Mode = .auto,
                             scope: TreeScope = .auto) throws -> SmartClickResult {
        let parsed = try Selector.parse(selector)

        // Try AX first.
        let tree = try TreeCache.shared.tree(target: target, maxDepth: 30, includeHidden: false, scope: scope)
        if let m = parsed.match(tree).first {
            _ = try Adapter.current.click(node: m, app: target, button: button, count: count, useAXPress: useAXPress)
            TreeCache.shared.invalidate(pid: target.pid)
            return SmartClickResult(path: "ax", selector: selector, detail: m.name ?? m.identifier, target: m.id)
        }

        // Decide whether to try OCR.
        switch mode {
        case .strict:
            throw GuiportError(code: "no_match",
                               message: "selector matched no element",
                               hint: "try `guiport find` to inspect, or drop --strict")
        case .auto:
            // Skip OCR silently if Screen Recording is missing — don't prompt mid-action.
            guard Adapter.current.hasScreenRecordingPermission() else {
                throw GuiportError(code: "no_match",
                                   message: "selector matched no element",
                                   hint: "OCR fallback skipped (Screen Recording not granted). Run `guiport doctor --fix` to enable.")
            }
        case .ocr:
            // User explicitly opted in — let the OCR call trigger the SR prompt if needed.
            break
        }

        guard let query = parsed.ocrQuery else {
            throw GuiportError(code: "no_ocr_query",
                               message: "selector has no name/text predicate to fall back on",
                               hint: "use a name=\"...\" predicate, call `click-text`, or pass --strict")
        }

        let matches = try Adapter.current.findText(in: target, query: query, exact: false, limit: 1)
        guard let m = matches.first else {
            throw GuiportError(code: "no_match_with_ocr",
                               message: "neither AX selector nor visual fallback matched \"\(query)\"",
                               hint: "try `guiport find-text --app \"\(target.name)\" \"\(query)\"` to inspect")
        }
        _ = try Adapter.current.clickAt(x: m.centerX, y: m.centerY, button: button, count: count)
        return SmartClickResult(
            path: "ocr",
            selector: selector,
            detail: "\(m.text) @ \(Int(m.centerX)),\(Int(m.centerY))",
            target: nil
        )
    }
}
