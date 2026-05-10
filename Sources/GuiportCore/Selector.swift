import Foundation

public struct Selector {
    public enum Op { case eq, contains }
    public struct Predicate {
        public let attr: String
        public let op: Op
        public let value: String
    }

    public let role: String?
    public let predicates: [Predicate]
    public let index: Int?

    /// Best-effort OCR query: pick the first text-bearing predicate value.
    /// `name`, `title`, `text`, `description`, `value` (in that order) — skip identifier/role.
    public var ocrQuery: String? {
        let order = ["name", "title", "text", "description", "value"]
        for key in order {
            if let p = predicates.first(where: { $0.attr.lowercased() == key }) {
                return p.value
            }
        }
        return nil
    }

    /// Parse `role[attr=value][attr~="substring"][index]`.
    /// `role` may be `*` or omitted.
    public static func parse(_ input: String) throws -> Selector {
        var s = input.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else {
            throw GuiportError(code: "selector_empty", message: "empty selector")
        }
        var role: String?
        var predicates: [Predicate] = []
        var index: Int?

        // role part: until first `[` or end
        if let firstBracket = s.firstIndex(of: "[") {
            let r = String(s[..<firstBracket])
            if !r.isEmpty, r != "*" {
                role = normalizedRole(r)
            }
            s = String(s[firstBracket...])
        } else {
            if s != "*" { role = normalizedRole(s) }
            s = ""
        }

        // each predicate: [name="Save"] or [name=Save] or [name~="Save"] or [3]
        while !s.isEmpty {
            guard s.first == "[" else {
                throw GuiportError(code: "selector_parse", message: "expected `[` at \"\(s)\"")
            }
            guard let end = s.firstIndex(of: "]") else {
                throw GuiportError(code: "selector_parse", message: "missing `]` in \"\(input)\"")
            }
            let inner = String(s[s.index(after: s.startIndex)..<end])
            if let n = Int(inner) {
                index = n
            } else {
                let pred = try parsePredicate(inner)
                predicates.append(pred)
            }
            s = String(s[s.index(after: end)...])
        }

        return Selector(role: role, predicates: predicates, index: index)
    }

    private static func parsePredicate(_ raw: String) throws -> Predicate {
        // attr=value, attr~=value
        let r = raw.trimmingCharacters(in: .whitespaces)
        if let range = r.range(of: "~=") {
            let attr = String(r[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let v = unquote(String(r[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            return Predicate(attr: attr, op: .contains, value: v)
        }
        if let range = r.range(of: "=") {
            let attr = String(r[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let v = unquote(String(r[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            return Predicate(attr: attr, op: .eq, value: v)
        }
        throw GuiportError(code: "selector_parse", message: "invalid predicate \"\(raw)\"")
    }

    private static func unquote(_ v: String) -> String {
        if v.count >= 2 {
            let f = v.first!, l = v.last!
            if (f == "\"" && l == "\"") || (f == "'" && l == "'") {
                return String(v.dropFirst().dropLast())
            }
        }
        return v
    }

    /// Allow `button` to match `AXButton`, `text` to match `AXStaticText` or `AXTextField`.
    private static func normalizedRole(_ r: String) -> String {
        let lower = r.lowercased()
        if lower.hasPrefix("ax") { return r }
        let map: [String: String] = [
            "button": "AXButton",
            "checkbox": "AXCheckBox",
            "radio": "AXRadioButton",
            "textfield": "AXTextField",
            "textarea": "AXTextArea",
            "menu": "AXMenu",
            "menuitem": "AXMenuItem",
            "popup": "AXPopUpButton",
            "image": "AXImage",
            "link": "AXLink",
            "list": "AXList",
            "row": "AXRow",
            "cell": "AXCell",
            "group": "AXGroup",
            "window": "AXWindow",
            "toolbar": "AXToolbar",
            "tab": "AXTab",
            "tabgroup": "AXTabGroup",
            "scrollarea": "AXScrollArea",
            "statictext": "AXStaticText",
            "text": "AXStaticText",
            "slider": "AXSlider",
            "splitter": "AXSplitter",
            "outline": "AXOutline",
        ]
        return map[lower] ?? r
    }

    // MARK: - Matching

    public func match(_ tree: AXNode) -> [AXNode] {
        var out: [AXNode] = []
        collect(tree, into: &out)
        if let idx = index {
            return idx < out.count ? [out[idx]] : []
        }
        return out
    }

    private func collect(_ node: AXNode, into out: inout [AXNode]) {
        if matches(node) { out.append(node) }
        for c in node.children { collect(c, into: &out) }
    }

    private func matches(_ node: AXNode) -> Bool {
        if let role {
            // exact match on role or subrole
            if node.role != role && node.subrole != role && !equalsLoose(node.role, role) {
                return false
            }
        }
        for p in predicates {
            if !matchPredicate(p, node: node) { return false }
        }
        return true
    }

    private func matchPredicate(_ p: Predicate, node: AXNode) -> Bool {
        let candidates: [String?]
        switch p.attr.lowercased() {
        case "name", "title": candidates = [node.name]
        case "value": candidates = [node.value]
        case "identifier", "id": candidates = [node.identifier]
        case "description", "desc": candidates = [node.description]
        case "help": candidates = [node.help]
        case "role": candidates = [node.role, node.subrole]
        case "subrole": candidates = [node.subrole]
        case "text": candidates = [node.name, node.value, node.description]
        default: candidates = []
        }
        for cand in candidates {
            guard let c = cand else { continue }
            switch p.op {
            case .eq: if c == p.value { return true }
            case .contains: if c.localizedCaseInsensitiveContains(p.value) { return true }
            }
        }
        return false
    }

    private func equalsLoose(_ a: String, _ b: String) -> Bool {
        return a.caseInsensitiveCompare(b) == .orderedSame
    }
}
