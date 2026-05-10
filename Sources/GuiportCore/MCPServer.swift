import Foundation

/// Minimal MCP-compatible JSON-RPC server over stdio.
/// Implements: initialize, tools/list, tools/call.
/// Tools: apps, doctor, observe, tree, find, click, type, hotkey, screenshot, run.
public enum MCPServer {
    public static func runStdio() async throws {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        let stderr = FileHandle.standardError

        stderr.write(Data("guiport MCP server ready\n".utf8))

        let buffer = LineBuffer()
        for try await line in stdin.bytes.lines {
            buffer.feed(line)
            while let frame = buffer.takeFrame() {
                await handleFrame(frame, out: stdout, err: stderr)
            }
        }
    }

    // MARK: - Framing

    /// MCP transports use JSON lines (one JSON object per line) over stdio.
    private final class LineBuffer {
        var pending: [String] = []
        func feed(_ line: String) {
            let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { pending.append(s) }
        }
        func takeFrame() -> String? {
            guard !pending.isEmpty else { return nil }
            return pending.removeFirst()
        }
    }

    // MARK: - Dispatch

    private static func handleFrame(_ frame: String, out: FileHandle, err: FileHandle) async {
        guard let data = frame.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            err.write(Data("invalid json: \(frame)\n".utf8))
            return
        }
        let id = obj["id"]
        let method = obj["method"] as? String ?? ""
        let params = obj["params"] as? [String: Any] ?? [:]

        do {
            let result: Any
            switch method {
            case "initialize":
                result = [
                    "protocolVersion": "2024-11-05",
                    "capabilities": ["tools": [String: Any]()],
                    "serverInfo": ["name": "guiport", "version": Guiport.version],
                ] as [String: Any]
            case "tools/list":
                result = ["tools": Tools.list]
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                let payload = try await Tools.call(name: name, args: args)
                result = ["content": [["type": "text", "text": payload]], "isError": false]
            case "ping":
                result = [String: Any]()
            case "notifications/initialized":
                return // notification, no reply
            default:
                throw GuiportError(code: "method_not_found", message: "unknown method `\(method)`")
            }
            try sendResponse(id: id, result: result, out: out)
        } catch let g as GuiportError {
            try? sendError(id: id, code: -32000, message: g.message, out: out)
        } catch {
            try? sendError(id: id, code: -32603, message: "\(error)", out: out)
        }
    }

    private static func sendResponse(id: Any?, result: Any, out: FileHandle) throws {
        var obj: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { obj["id"] = id }
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])
        out.write(data)
        out.write(Data("\n".utf8))
    }

    private static func sendError(id: Any?, code: Int, message: String, out: FileHandle) throws {
        var obj: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id { obj["id"] = id }
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])
        out.write(data)
        out.write(Data("\n".utf8))
    }
}

// MARK: - Tools

private enum Tools {
    static let list: [[String: Any]] = [
        tool(name: "doctor", desc: "Check guiport readiness (permissions).",
             props: [:]),
        tool(name: "apps", desc: "List running apps with windows.",
             props: ["with_windows": ["type": "boolean"]]),
        tool(name: "observe", desc: "Summarize focused window of an app.",
             props: ["app": ["type": "string"], "window": ["type": "string"]]),
        tool(name: "tree", desc: "Dump the accessibility tree of an app's focused window.",
             props: ["app": ["type": "string"], "window": ["type": "string"], "max_depth": ["type": "integer"]]),
        tool(name: "find", desc: "Find elements matching a selector.",
             props: ["app": ["type": "string"], "selector": ["type": "string"], "all": ["type": "boolean"]],
             required: ["selector"]),
        tool(name: "click", desc: "Click an element matched by selector.",
             props: ["app": ["type": "string"], "selector": ["type": "string"], "press": ["type": "boolean"]],
             required: ["selector"]),
        tool(name: "click_at", desc: "Click at raw screen coordinates (vision/OCR fallback).",
             props: ["x": ["type": "number"], "y": ["type": "number"], "button": ["type": "string"]],
             required: ["x", "y"]),
        tool(name: "type", desc: "Type text into the focused element.",
             props: ["text": ["type": "string"], "delay_ms": ["type": "integer"]],
             required: ["text"]),
        tool(name: "hotkey", desc: "Send a hotkey combo, e.g. cmd+shift+t.",
             props: ["combo": ["type": "string"]],
             required: ["combo"]),
        tool(name: "screenshot", desc: "Capture a screenshot. Defaults to artifacts/.",
             props: ["app": ["type": "string"], "out": ["type": "string"]]),
        tool(name: "run", desc: "Run a YAML replay test.",
             props: ["path": ["type": "string"], "artifacts": ["type": "string"]],
             required: ["path"]),
    ]

    static func call(name: String, args: [String: Any]) async throws -> String {
        switch name {
        case "doctor":
            return try JSONOutput.encode(Doctor.checkAll(), pretty: true)
        case "apps":
            let withWindows = (args["with_windows"] as? Bool) ?? false
            return try JSONOutput.encode(try AppRegistry.list(onlyWithWindows: withWindows), pretty: true)
        case "observe":
            let target = try AppRegistry.resolve(name: args["app"] as? String, windowTitle: args["window"] as? String)
            return try JSONOutput.encode(try AXBridge.observe(target: target), pretty: true)
        case "tree":
            let target = try AppRegistry.resolve(name: args["app"] as? String, windowTitle: args["window"] as? String)
            let depth = (args["max_depth"] as? Int) ?? 30
            return try JSONOutput.encode(try AXBridge.tree(target: target, maxDepth: depth, includeHidden: false), pretty: true)
        case "find":
            guard let sel = args["selector"] as? String else { throw GuiportError(code: "missing_arg", message: "selector required") }
            let target = try AppRegistry.resolve(name: args["app"] as? String, windowTitle: args["window"] as? String)
            let tree = try AXBridge.tree(target: target, maxDepth: 30, includeHidden: false)
            let parsed = try Selector.parse(sel)
            let all = (args["all"] as? Bool) ?? false
            let nodes = parsed.match(tree)
            return try JSONOutput.encode(all ? nodes : Array(nodes.prefix(1)), pretty: true)
        case "click":
            guard let sel = args["selector"] as? String else { throw GuiportError(code: "missing_arg", message: "selector required") }
            let target = try AppRegistry.resolve(name: args["app"] as? String, windowTitle: args["window"] as? String)
            let tree = try AXBridge.tree(target: target, maxDepth: 30, includeHidden: false)
            let parsed = try Selector.parse(sel)
            guard let m = parsed.match(tree).first else {
                throw GuiportError(code: "no_match", message: "selector matched no element")
            }
            let usePress = (args["press"] as? Bool) ?? false
            return try JSONOutput.encode(try Input.click(m, app: target, button: "left", count: 1, useAXPress: usePress), pretty: true)
        case "click_at":
            guard let x = (args["x"] as? NSNumber)?.doubleValue,
                  let y = (args["y"] as? NSNumber)?.doubleValue else {
                throw GuiportError(code: "missing_arg", message: "x and y required")
            }
            let button = (args["button"] as? String) ?? "left"
            return try JSONOutput.encode(try Input.clickAt(x: x, y: y, button: button), pretty: true)
        case "type":
            guard let text = args["text"] as? String else { throw GuiportError(code: "missing_arg", message: "text required") }
            let delay = (args["delay_ms"] as? Int) ?? 0
            return try JSONOutput.encode(try Input.type(text, perCharDelayMs: delay), pretty: true)
        case "hotkey":
            guard let combo = args["combo"] as? String else { throw GuiportError(code: "missing_arg", message: "combo required") }
            return try JSONOutput.encode(try Input.hotkey(combo), pretty: true)
        case "screenshot":
            let target: AppTarget? = (args["app"] as? String) != nil ?
                try AppRegistry.resolve(name: args["app"] as? String, windowTitle: args["window"] as? String) : nil
            let path = (args["out"] as? String) ?? Screenshot.defaultPath()
            return try JSONOutput.encode(try Screenshot.capture(target: target, to: path), pretty: true)
        case "run":
            guard let path = args["path"] as? String else { throw GuiportError(code: "missing_arg", message: "path required") }
            let dir = (args["artifacts"] as? String) ?? "artifacts"
            return try JSONOutput.encode(try await Runner.run(path: path, artifactsDir: dir), pretty: true)
        default:
            throw GuiportError(code: "unknown_tool", message: "unknown tool `\(name)`")
        }
    }

    private static func tool(name: String, desc: String, props: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": desc, "inputSchema": schema]
    }
}
