import Foundation

public struct SmartClickResult: Encodable {
    public let path: String   // "ax" | "ocr"
    public let selector: String
    public let detail: String?
    public let target: String?
}

/// Tries AX selectors first; on no-match, falls back to OCR using the selector's name/text predicate.
/// `fallback` controls what happens when AX misses:
///   - .none  : throw no_match.
///   - .ocr   : try OCR; throw if that also misses.
public enum SmartClick {
    public enum Fallback: String { case none, ocr }

    public static func click(selector: String,
                             target: AppTarget,
                             button: String = "left",
                             count: Int = 1,
                             useAXPress: Bool = false,
                             fallback: Fallback = .none) throws -> SmartClickResult {
        let parsed = try Selector.parse(selector)

        // Try AX first.
        let tree = try TreeCache.shared.tree(target: target, maxDepth: 30, includeHidden: false)
        if let m = parsed.match(tree).first {
            _ = try Input.click(m, app: target, button: button, count: count, useAXPress: useAXPress)
            TreeCache.shared.invalidate(pid: target.pid)
            return SmartClickResult(path: "ax", selector: selector, detail: m.name ?? m.identifier, target: m.id)
        }

        guard fallback == .ocr else {
            throw GuiportError(code: "no_match",
                               message: "selector matched no element",
                               hint: "try `guiport find` to inspect, or pass --fallback ocr")
        }

        guard let query = parsed.ocrQuery else {
            throw GuiportError(code: "no_ocr_query",
                               message: "selector has no name/text predicate to OCR-fallback on",
                               hint: "use a name=\"...\" predicate or call `click-text` directly")
        }

        let matches = try OCR.findText(in: target, query: query, exact: false, limit: 1)
        guard let m = matches.first else {
            throw GuiportError(code: "no_match_with_ocr",
                               message: "neither AX selector nor OCR matched \"\(query)\"",
                               hint: "try `guiport find-text --app \"\(target.name)\" \"\(query)\"` to inspect")
        }
        _ = try Input.clickAt(x: m.centerX, y: m.centerY, button: button, count: count)
        return SmartClickResult(
            path: "ocr",
            selector: selector,
            detail: "\(m.text) @ \(Int(m.centerX)),\(Int(m.centerY))",
            target: nil
        )
    }
}
