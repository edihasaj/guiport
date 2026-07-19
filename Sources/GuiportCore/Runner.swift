import Foundation

public struct StepResult: Encodable {
    public let action: String
    public let passed: Bool
    public let durationMs: Int
    public let detail: String?
    public let error: String?
}

public struct RunResult: Encodable {
    public let path: String
    public let passed: Bool
    public let steps: [StepResult]
    public let artifactsDir: String
    public let failureArtifacts: [String]?
}

/// YAML schema:
///
///   name: my smoke
///   app: Safari
///   timeout_ms: 5000
///   steps:
///     - wait: 200
///     - find: 'button[name="Save"]'
///     - click: 'button[name="Save"]'
///     - type: "hello"
///     - hotkey: "cmd+s"
///     - screenshot: out.png      # optional path; default artifacts/
///     - assert:
///         find: 'AXStaticText[name~="Saved"]'
///         exists: true
///
public enum Runner {
    public static func run(path: String, artifactsDir: String) async throws -> RunResult {
        let url = URL(fileURLWithPath: path)
        let raw = try String(contentsOf: url, encoding: .utf8)
        let parsed = try parseFlow(raw)

        try? FileManager.default.createDirectory(atPath: artifactsDir, withIntermediateDirectories: true)

        let appName = parsed["app"] as? String
        let defaultTimeoutMs = (parsed["timeout_ms"] as? Int) ?? 5000
        let steps = (parsed["steps"] as? [Any]) ?? []

        var results: [StepResult] = []
        var passed = true
        var failureArtifacts: [String] = []

        for (i, raw) in steps.enumerated() {
            let started = Date()
            do {
                let label = try await execStep(raw, appName: appName, timeoutMs: defaultTimeoutMs)
                results.append(.init(
                    action: label.action, passed: true,
                    durationMs: ms(since: started), detail: label.detail, error: nil
                ))
            } catch let g as GuiportError {
                let arts = saveFailureArtifacts(stepIndex: i, dir: artifactsDir, appName: appName, action: actionLabel(of: raw))
                failureArtifacts.append(contentsOf: arts)
                results.append(.init(
                    action: actionLabel(of: raw), passed: false,
                    durationMs: ms(since: started), detail: nil, error: "\(g)"
                ))
                passed = false
                break
            } catch {
                let arts = saveFailureArtifacts(stepIndex: i, dir: artifactsDir, appName: appName, action: actionLabel(of: raw))
                failureArtifacts.append(contentsOf: arts)
                results.append(.init(
                    action: actionLabel(of: raw), passed: false,
                    durationMs: ms(since: started), detail: nil, error: "\(error)"
                ))
                passed = false
                break
            }
        }

        return RunResult(
            path: path, passed: passed, steps: results, artifactsDir: artifactsDir,
            failureArtifacts: failureArtifacts.isEmpty ? nil : failureArtifacts
        )
    }

    /// Execute a pre-parsed list of steps against `appName`, stopping at the
    /// first failure. This is the shared engine behind both `run` (YAML flows)
    /// and `guiport plugin run` (named plugin actions) — same step grammar, same
    /// failure-artifact capture, same `RunResult` shape. `label` identifies the
    /// source in the result (`path` for flows, `plugin:<name>/<action>` for
    /// plugin actions).
    public static func runSteps(
        _ steps: [Any], label: String, appName: String?, timeoutMs: Int, artifactsDir: String
    ) async -> RunResult {
        try? FileManager.default.createDirectory(atPath: artifactsDir, withIntermediateDirectories: true)

        var results: [StepResult] = []
        var passed = true
        var failureArtifacts: [String] = []

        for (i, raw) in steps.enumerated() {
            let started = Date()
            do {
                let step = try await execStep(raw, appName: appName, timeoutMs: timeoutMs)
                results.append(.init(
                    action: step.action, passed: true,
                    durationMs: ms(since: started), detail: step.detail, error: nil
                ))
            } catch {
                let arts = saveFailureArtifacts(
                    stepIndex: i, dir: artifactsDir, appName: appName, action: actionLabel(of: raw)
                )
                failureArtifacts.append(contentsOf: arts)
                results.append(.init(
                    action: actionLabel(of: raw), passed: false,
                    durationMs: ms(since: started), detail: nil, error: "\(error)"
                ))
                passed = false
                break
            }
        }

        return RunResult(
            path: label, passed: passed, steps: results, artifactsDir: artifactsDir,
            failureArtifacts: failureArtifacts.isEmpty ? nil : failureArtifacts
        )
    }

    private static func parseFlow(_ raw: String) throws -> [String: Any] {
        var result: [String: Any] = [:]
        let lines = raw.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = stripComment(lines[index]).trimmingCharacters(in: .whitespaces)
            index += 1
            if line.isEmpty { continue }

            if line == "steps:" {
                result["steps"] = try parseStepList(lines, &index, minIndent: 1)
                continue
            }

            let (key, value) = try splitMapping(line)
            result[key] = parseScalar(value)
        }

        guard result["steps"] is [Any] else {
            throw GuiportError(code: "yaml_parse", message: "test file needs `steps:`")
        }
        return result
    }

    /// Parse a YAML block of `- key: value` step items (with optional nested
    /// mappings) starting at `index`. The item column is auto-detected from the
    /// first item; parsing stops at the first non-blank line indented less than
    /// that column (a dedent), leaving `index` on it. `minIndent` is the floor
    /// the first item must reach to count as part of the block — used so a
    /// `steps:` key with no indented items yields an empty list rather than
    /// swallowing following siblings. Shared by the flow runner and the plugin
    /// action loader so both understand the exact same step grammar.
    static func parseStepList(_ lines: [String], _ index: inout Int, minIndent: Int) throws -> [Any] {
        var steps: [Any] = []
        var itemIndent = -1
        while index < lines.count {
            let rawStep = stripComment(lines[index])
            let trimmed = rawStep.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }
            let indent = leadingSpaces(rawStep)
            if itemIndent < 0 {
                if indent < minIndent { break }
                itemIndent = indent
            }
            if indent < itemIndent { break }
            guard trimmed.hasPrefix("- ") else {
                throw GuiportError(code: "yaml_parse", message: "step must start with `- `")
            }
            let item = String(trimmed.dropFirst(2))
            let (key, valueText) = try splitMapping(item)
            index += 1

            if valueText.isEmpty {
                var nested: [String: Any] = [:]
                while index < lines.count {
                    let rawNested = stripComment(lines[index])
                    let nestedTrimmed = rawNested.trimmingCharacters(in: .whitespaces)
                    if nestedTrimmed.isEmpty { index += 1; continue }
                    if leadingSpaces(rawNested) <= itemIndent { break }
                    let (nestedKey, nestedValue) = try splitMapping(nestedTrimmed)
                    nested[nestedKey] = parseScalar(nestedValue)
                    index += 1
                }
                steps.append([key: nested])
            } else {
                steps.append([key: parseScalar(valueText)])
            }
        }
        return steps
    }

    /// Count leading indentation, treating a tab as four columns.
    static func leadingSpaces(_ s: String) -> Int {
        var n = 0
        for ch in s {
            if ch == " " { n += 1 }
            else if ch == "\t" { n += 4 }
            else { break }
        }
        return n
    }

    static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        for (idx, ch) in line.enumerated() {
            if ch == "'" && !inDouble { inSingle.toggle() }
            if ch == "\"" && !inSingle { inDouble.toggle() }
            if ch == "#" && !inSingle && !inDouble {
                let i = line.index(line.startIndex, offsetBy: idx)
                return String(line[..<i])
            }
        }
        return line
    }

    static func splitMapping(_ line: String) throws -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else {
            throw GuiportError(code: "yaml_parse", message: "expected `key: value`, got `\(line)`")
        }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if key.isEmpty {
            throw GuiportError(code: "yaml_parse", message: "mapping key is empty")
        }
        return (key, value)
    }

    static func parseScalar(_ value: String) -> Any {
        if value == "true" { return true }
        if value == "false" { return false }
        if let int = Int(value) { return int }
        if value.hasPrefix("["), value.hasSuffix("]") {
            let body = value.dropFirst().dropLast()
            return body.split(separator: ",").map { parseScalar($0.trimmingCharacters(in: .whitespaces)) }
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: - Step execution

    private struct StepLabel {
        let action: String
        let detail: String?
    }

    private static func execStep(_ raw: Any, appName: String?, timeoutMs: Int) async throws -> StepLabel {
        guard let dict = raw as? [String: Any], let (key, value) = dict.first else {
            throw GuiportError(code: "step_parse", message: "step is not a mapping")
        }

        switch key {
        case "wait":
            let ms = (value as? Int) ?? 0
            try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            return .init(action: "wait", detail: "\(ms)ms")

        case "activate":
            // `activate: true` foregrounds the flow/plugin app; `activate: <app>`
            // targets a different app. Raises without relaunch or a synthetic
            // click, so keystrokes land where the flow intends.
            let target: String?
            if let s = value as? String { target = s } else { target = appName }
            guard let name = target else {
                throw GuiportError(code: "step_parse", message: "activate needs an app (set the flow `app:` or `activate: <app>`)")
            }
            let resolved = try Adapter.current.resolveApp(name: name)
            _ = try Adapter.current.activate(target: resolved)
            return .init(action: "activate", detail: name)

        case "find":
            guard let sel = value as? String else { throw GuiportError(code: "step_parse", message: "find expects a string selector") }
            let target = try Adapter.current.resolveApp(name: appName)
            try await waitFor(selector: sel, target: target, timeoutMs: timeoutMs)
            return .init(action: "find", detail: sel)

        case "click":
            // Accept "click: selector" or "click: { selector, strict: true }".
            let (sel, strict) = parseClickStep(value)
            let target = try Adapter.current.resolveApp(name: appName)
            // Wait for the selector to appear, then dispatch through SmartClick which
            // handles the auto visual fallback (skips silently if SR not granted).
            try await waitFor(selector: sel, target: target, timeoutMs: timeoutMs)
            let result = try SmartClick.click(
                selector: sel, target: target,
                mode: strict ? .strict : .auto
            )
            return .init(action: "click", detail: "\(sel) [\(result.path)]")

        case "click_text":
            guard let q = value as? String else { throw GuiportError(code: "step_parse", message: "click_text expects a string query") }
            let target: AppTarget? = appName != nil ? try Adapter.current.resolveApp(name: appName) : nil
            let matches = try Adapter.current.findText(in: target, query: q, exact: false, limit: 1)
            guard let m = matches.first else {
                throw GuiportError(code: "ocr_no_match", message: "OCR did not find: \(q)")
            }
            _ = try Adapter.current.clickAt(x: m.centerX, y: m.centerY)
            return .init(action: "click_text", detail: q)

        case "find_text":
            guard let q = value as? String else { throw GuiportError(code: "step_parse", message: "find_text expects a string query") }
            let target: AppTarget? = appName != nil ? try Adapter.current.resolveApp(name: appName) : nil
            let matches = try Adapter.current.findText(in: target, query: q, exact: false, limit: 1)
            if matches.isEmpty {
                throw GuiportError(code: "ocr_no_match", message: "OCR did not find: \(q)")
            }
            return .init(action: "find_text", detail: q)

        case "click_at":
            // Accept either "click_at: [x, y]" or "click_at: {x: 10, y: 20}"
            let (x, y) = try parseCoords(value)
            _ = try Adapter.current.clickAt(x: x, y: y)
            return .init(action: "click_at", detail: "\(Int(x)),\(Int(y))")

        case "press":
            guard let sel = value as? String else { throw GuiportError(code: "step_parse", message: "press expects a selector") }
            let target = try Adapter.current.resolveApp(name: appName)
            let node = try await waitFor(selector: sel, target: target, timeoutMs: timeoutMs)
            _ = try Adapter.current.click(node: node, app: target, button: "left", count: 1, useAXPress: true)
            return .init(action: "press", detail: sel)

        case "type":
            guard let text = value as? String else { throw GuiportError(code: "step_parse", message: "type expects a string") }
            _ = try Adapter.current.type(text: text, perCharDelayMs: 0)
            return .init(action: "type", detail: "\(text.count) chars")

        case "hotkey":
            guard let combo = value as? String else { throw GuiportError(code: "step_parse", message: "hotkey expects a string") }
            _ = try Adapter.current.hotkey(combo: combo)
            return .init(action: "hotkey", detail: combo)

        case "screenshot":
            let target: AppTarget? = appName != nil ? try Adapter.current.resolveApp(name: appName) : nil
            let path = (value as? String) ?? Adapter.current.defaultScreenshotPath()
            let r = try Adapter.current.captureScreenshot(target: target, to: path)
            return .init(action: "screenshot", detail: r.path)

        case "assert":
            guard let dict = value as? [String: Any] else {
                throw GuiportError(code: "step_parse", message: "assert expects a mapping")
            }
            // Predicates mirror `guiport assert`: element existence (`find`/`exists`)
            // plus cheap state checks (`frontmost`, `front_title_contains`,
            // `focused`) so flows/plugins can verify they're where they think
            // they are before typing. At least one predicate is required.
            let target = try Adapter.current.resolveApp(name: appName)
            var detail: [String] = []
            var checked = false

            if let sel = dict["find"] as? String {
                checked = true
                detail.append(sel)
                let exists = (dict["exists"] as? Bool) ?? true
                do {
                    _ = try await waitFor(selector: sel, target: target, timeoutMs: timeoutMs)
                    if !exists {
                        throw GuiportError(code: "assert_failed", message: "\(sel) exists, expected absent")
                    }
                } catch {
                    if exists { throw error }
                }
            }

            if let front = dict["frontmost"] as? Bool, front {
                checked = true
                detail.append("frontmost")
                let f = Adapter.current.frontmostApp()
                if f?.pid != target.pid {
                    throw GuiportError(code: "assert_failed", message: "\(appName ?? "app") is not frontmost (front: \(f?.name ?? "unknown"))")
                }
            }

            if let needle = dict["front_title_contains"] as? String {
                checked = true
                detail.append("title~\(needle)")
                let title = (try? Adapter.current.observe(target: target))?.window?.title
                if title?.range(of: needle, options: .caseInsensitive) == nil {
                    throw GuiportError(code: "assert_failed", message: "front title \"\(title ?? "nil")\" does not contain \"\(needle)\"")
                }
            }

            if let sel = dict["focused"] as? String {
                checked = true
                detail.append("focused:\(sel)")
                let parsed = try Selector.parse(sel)
                let tree = try Adapter.current.tree(target: target)
                if !parsed.match(tree).contains(where: { $0.focused == true }) {
                    throw GuiportError(code: "assert_failed", message: "no focused element matches \(sel)")
                }
            }

            guard checked else {
                throw GuiportError(code: "step_parse", message: "assert needs one of `find`, `frontmost`, `front_title_contains`, `focused`")
            }
            return .init(action: "assert", detail: detail.joined(separator: ", "))

        default:
            throw GuiportError(code: "unknown_step", message: "unknown step `\(key)`")
        }
    }

    @discardableResult
    private static func waitFor(selector: String, target: AppTarget, timeoutMs: Int) async throws -> AXNode {
        let parsed = try Selector.parse(selector)
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var lastErr: Error?
        while Date() < deadline {
            do {
                // Force fresh during polling — UI is changing.
                TreeCache.shared.invalidate(pid: target.pid)
                let tree = try TreeCache.shared.tree(target: target, maxDepth: 30, includeHidden: false)
                if let m = parsed.match(tree).first { return m }
            } catch {
                lastErr = error
            }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        if let lastErr { throw lastErr }
        throw GuiportError(code: "timeout", message: "selector did not match within \(timeoutMs)ms: \(selector)")
    }

    // MARK: - Failure artifacts

    private static func saveFailureArtifacts(stepIndex: Int, dir: String, appName: String?, action: String) -> [String] {
        var saved: [String] = []
        let stamp = String(Int(Date().timeIntervalSince1970))
        let prefix = "\(dir)/fail-\(stamp)-step\(stepIndex)-\(action)"

        // tree
        if let appName, let target = try? Adapter.current.resolveApp(name: appName),
           let tree = try? Adapter.current.tree(target: target),
           let json = try? JSONOutput.encode(tree, pretty: true) {
            let p = "\(prefix)-tree.json"
            try? json.write(toFile: p, atomically: true, encoding: .utf8)
            saved.append(p)
        }
        // screenshot
        if let appName, let target = try? Adapter.current.resolveApp(name: appName) {
            let p = "\(prefix)-screen.png"
            if (try? Adapter.current.captureScreenshot(target: target, to: p)) != nil { saved.append(p) }
        } else if (try? Adapter.current.captureScreenshot(target: nil, to: "\(prefix)-screen.png")) != nil {
            saved.append("\(prefix)-screen.png")
        }
        return saved
    }

    /// Parse `click: <selector>` or `click: { selector, strict }`. Visual fallback is on by
    /// default; pass `strict: true` to disable.
    private static func parseClickStep(_ value: Any) -> (String, Bool) {
        if let s = value as? String { return (s, false) }
        if let d = value as? [String: Any] {
            let sel = (d["selector"] as? String) ?? ""
            // Back-compat: "fallback: none" → strict; otherwise honor `strict`.
            let strictFlag = (d["strict"] as? Bool) ?? ((d["fallback"] as? String)?.lowercased() == "none")
            return (sel, strictFlag)
        }
        return ("", false)
    }

    private static func parseCoords(_ value: Any) throws -> (Double, Double) {
        if let arr = value as? [Any], arr.count == 2 {
            let x = (arr[0] as? NSNumber)?.doubleValue ?? Double("\(arr[0])") ?? 0
            let y = (arr[1] as? NSNumber)?.doubleValue ?? Double("\(arr[1])") ?? 0
            return (x, y)
        }
        if let dict = value as? [String: Any] {
            let x = (dict["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (dict["y"] as? NSNumber)?.doubleValue ?? 0
            return (x, y)
        }
        throw GuiportError(code: "step_parse", message: "click_at expects [x, y] or {x, y}")
    }

    private static func actionLabel(of raw: Any) -> String {
        if let dict = raw as? [String: Any], let k = dict.keys.first { return k }
        return "unknown"
    }

    private static func ms(since start: Date) -> Int {
        return Int(Date().timeIntervalSince(start) * 1000)
    }
}
