import Foundation
import Yams

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
        let parsed = try Yams.load(yaml: raw) as? [String: Any]
            ?? { throw GuiportError(code: "yaml_parse", message: "test file is not a mapping") }()

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

        case "find":
            guard let sel = value as? String else { throw GuiportError(code: "step_parse", message: "find expects a string selector") }
            let target = try AppRegistry.resolve(name: appName)
            try await waitFor(selector: sel, target: target, timeoutMs: timeoutMs)
            return .init(action: "find", detail: sel)

        case "click":
            guard let sel = value as? String else { throw GuiportError(code: "step_parse", message: "click expects a selector") }
            let target = try AppRegistry.resolve(name: appName)
            let node = try await waitFor(selector: sel, target: target, timeoutMs: timeoutMs)
            _ = try Input.click(node, app: target, button: "left", count: 1, useAXPress: false)
            return .init(action: "click", detail: sel)

        case "click_at":
            // Accept either "click_at: [x, y]" or "click_at: {x: 10, y: 20}"
            let (x, y) = try parseCoords(value)
            _ = try Input.clickAt(x: x, y: y)
            return .init(action: "click_at", detail: "\(Int(x)),\(Int(y))")

        case "press":
            guard let sel = value as? String else { throw GuiportError(code: "step_parse", message: "press expects a selector") }
            let target = try AppRegistry.resolve(name: appName)
            let node = try await waitFor(selector: sel, target: target, timeoutMs: timeoutMs)
            _ = try Input.click(node, app: target, button: "left", count: 1, useAXPress: true)
            return .init(action: "press", detail: sel)

        case "type":
            guard let text = value as? String else { throw GuiportError(code: "step_parse", message: "type expects a string") }
            _ = try Input.type(text, perCharDelayMs: 0)
            return .init(action: "type", detail: "\(text.count) chars")

        case "hotkey":
            guard let combo = value as? String else { throw GuiportError(code: "step_parse", message: "hotkey expects a string") }
            _ = try Input.hotkey(combo)
            return .init(action: "hotkey", detail: combo)

        case "screenshot":
            let target: AppTarget? = appName != nil ? try AppRegistry.resolve(name: appName) : nil
            let path = (value as? String) ?? Screenshot.defaultPath()
            let r = try Screenshot.capture(target: target, to: path)
            return .init(action: "screenshot", detail: r.path)

        case "assert":
            guard let dict = value as? [String: Any] else {
                throw GuiportError(code: "step_parse", message: "assert expects a mapping")
            }
            guard let sel = dict["find"] as? String else {
                throw GuiportError(code: "step_parse", message: "assert needs `find: selector`")
            }
            let exists = (dict["exists"] as? Bool) ?? true
            let target = try AppRegistry.resolve(name: appName)
            do {
                _ = try await waitFor(selector: sel, target: target, timeoutMs: timeoutMs)
                if !exists {
                    throw GuiportError(code: "assert_failed", message: "\(sel) exists, expected absent")
                }
            } catch {
                if exists { throw error }
            }
            return .init(action: "assert", detail: sel)

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
        if let appName, let target = try? AppRegistry.resolve(name: appName),
           let tree = try? AXBridge.tree(target: target),
           let json = try? JSONOutput.encode(tree, pretty: true) {
            let p = "\(prefix)-tree.json"
            try? json.write(toFile: p, atomically: true, encoding: .utf8)
            saved.append(p)
        }
        // screenshot
        if let appName, let target = try? AppRegistry.resolve(name: appName) {
            let p = "\(prefix)-screen.png"
            if (try? Screenshot.capture(target: target, to: p)) != nil { saved.append(p) }
        } else if (try? Screenshot.capture(target: nil, to: "\(prefix)-screen.png")) != nil {
            saved.append("\(prefix)-screen.png")
        }
        return saved
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
