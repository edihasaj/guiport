import Foundation

/// A named, reusable automation composed of existing guiport primitives. Plugins
/// live in a user directory (default `~/.guiport/plugins/*.{yaml,yml}`) so
/// personal or private automations never ship in core — guiport itself carries
/// zero app-specific knowledge. Each plugin targets one app and exposes one or
/// more named **actions**; an action is just a list of flow steps (the same
/// grammar as `guiport run`), so it can foreground the app, navigate, assert
/// state, and type — reliably and repeatably — from a single command.
public struct GuiportPlugin: Encodable {
    public let name: String
    /// Target app: bundle id or display name. Actions inherit it unless the run
    /// overrides it. Optional so a plugin can be a pure step library.
    public let app: String?
    public let description: String?
    /// Absolute path the plugin was loaded from (nil for in-memory plugins).
    public let path: String?
    public let actions: [PluginAction]

    public init(name: String, app: String?, description: String?, path: String?, actions: [PluginAction]) {
        self.name = name
        self.app = app
        self.description = description
        self.path = path
        self.actions = actions
    }

    public func action(named: String) -> PluginAction? {
        actions.first { $0.name == named }
    }
}

/// One named action within a plugin. `params` are the placeholders the action's
/// steps reference as `{{name}}` (or `{{name|default}}`); required params must be
/// supplied at run time. `steps` is intentionally untyped (`[Any]`) — it is the
/// parsed flow-step list handed straight to `Runner.runSteps`.
public struct PluginAction: Encodable {
    public let name: String
    public let description: String?
    public let params: [String]
    public let steps: [Any]

    public init(name: String, description: String?, params: [String], steps: [Any]) {
        self.name = name
        self.description = description
        self.params = params
        self.steps = steps
    }

    // `steps` holds parsed YAML (`[Any]`), which isn't Encodable; expose only the
    // declarative surface (name/description/params + step count) to `plugin list`.
    enum CodingKeys: String, CodingKey { case name, description, params, stepCount }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(params, forKey: .params)
        try c.encode(steps.count, forKey: .stepCount)
    }
}

/// Discovery, loading, and execution of plugins.
public enum PluginStore {
    /// Where plugins live. `GUIPORT_PLUGINS_DIR` overrides for tests / custom
    /// setups; otherwise `~/.guiport/plugins`.
    public static func defaultDir() -> String {
        if let env = ProcessInfo.processInfo.environment["GUIPORT_PLUGINS_DIR"], !env.isEmpty {
            return env
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".guiport/plugins").path
    }

    /// Every valid plugin in `dir` (default dir when nil), sorted by filename.
    /// A missing directory is not an error — it just yields no plugins. Files
    /// that fail to parse are skipped so one broken plugin can't hide the rest.
    public static func list(dir: String? = nil) -> [GuiportPlugin] {
        let d = dir ?? defaultDir()
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: d, isDirectory: &isDir), isDir.boolValue else { return [] }
        let entries = ((try? fm.contentsOfDirectory(atPath: d)) ?? []).sorted()
        var plugins: [GuiportPlugin] = []
        for entry in entries {
            let lower = entry.lowercased()
            guard lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") else { continue }
            if let p = try? parseFile(d + "/" + entry) { plugins.append(p) }
        }
        return plugins
    }

    /// Load a single plugin by name (filename stem or declared `name:`), or by a
    /// direct path to a `.yaml`/`.yml` file.
    public static func load(name: String, dir: String? = nil) throws -> GuiportPlugin {
        let fm = FileManager.default
        let lower = name.lowercased()
        if (lower.hasSuffix(".yaml") || lower.hasSuffix(".yml")), fm.fileExists(atPath: name) {
            return try parseFile(name)
        }
        let d = dir ?? defaultDir()
        for ext in ["yaml", "yml"] {
            let candidate = d + "/" + name + "." + ext
            if fm.fileExists(atPath: candidate) { return try parseFile(candidate) }
        }
        if let match = list(dir: dir).first(where: { $0.name == name }) { return match }
        throw GuiportError(
            code: "plugin_not_found",
            message: "no plugin named `\(name)` in \(d)",
            hint: "List available plugins with `guiport plugin list`."
        )
    }

    static func parseFile(_ path: String) throws -> GuiportPlugin {
        let raw = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return try PluginParser.parse(raw, path: path, defaultName: stem)
    }

    /// Run `action` of `plugin`, substituting `args` into its steps, then hand
    /// the resulting steps to the shared flow engine. `appOverride` wins over the
    /// plugin's declared app. Throws before running for an unknown action or a
    /// missing required param, so failures are clearly attributable.
    public static func run(
        plugin: GuiportPlugin,
        action actionName: String,
        args: [String: String],
        appOverride: String? = nil,
        artifactsDir: String = "artifacts",
        timeoutMs: Int = 5000
    ) async throws -> RunResult {
        guard let action = plugin.action(named: actionName) else {
            throw GuiportError(
                code: "action_not_found",
                message: "plugin `\(plugin.name)` has no action `\(actionName)`",
                hint: "Actions: \(plugin.actions.map { $0.name }.joined(separator: ", "))"
            )
        }
        for param in action.params where args[param] == nil {
            throw GuiportError(
                code: "missing_param",
                message: "action `\(actionName)` requires param `\(param)`",
                hint: "Pass it as `\(param)=<value>`."
            )
        }
        let substituted = try Substitution.apply(to: action.steps, args: args)
        let appName = appOverride ?? plugin.app
        let label = "plugin:\(plugin.name)/\(actionName)"
        return await Runner.runSteps(
            substituted as? [Any] ?? [],
            label: label, appName: appName, timeoutMs: timeoutMs, artifactsDir: artifactsDir
        )
    }
}

// MARK: - Parameter substitution

/// Expands `{{name}}` / `{{name|default}}` placeholders in an action's steps
/// using the supplied args. A step value that is *only* a single placeholder is
/// re-scalar-parsed after expansion, so `wait: {{ms}}` with `ms=80` becomes the
/// integer 80 rather than the string "80".
enum Substitution {
    static func apply(to value: Any, args: [String: String]) throws -> Any {
        switch value {
        case let s as String:
            return try expandScalar(s, args)
        case let arr as [Any]:
            return try arr.map { try apply(to: $0, args: args) }
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = try apply(to: v, args: args) }
            return out
        default:
            return value
        }
    }

    private static func expandScalar(_ s: String, _ args: [String: String]) throws -> Any {
        guard s.contains("{{") else { return s }
        let expanded = try expand(s, args)
        // Whole value was one placeholder → re-type it (numbers/bools/lists).
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}"),
           trimmed.range(of: "{{", range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex) == nil {
            return Runner.parseScalar(expanded)
        }
        return expanded
    }

    private static func expand(_ s: String, _ args: [String: String]) throws -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "{",
               let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex, s[next] == "{" {
                let scanFrom = s.index(next, offsetBy: 1)
                guard let close = s.range(of: "}}", range: scanFrom..<s.endIndex) else {
                    throw GuiportError(code: "plugin_template", message: "unclosed `{{` in `\(s)`")
                }
                let inner = String(s[scanFrom..<close.lowerBound])
                let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let fallback = parts.count > 1 ? String(parts[1]) : nil
                if let v = args[key] {
                    result += v
                } else if let fallback {
                    result += fallback
                } else {
                    throw GuiportError(
                        code: "missing_param",
                        message: "no value for param `\(key)`",
                        hint: "Pass `\(key)=<value>` or give it a default: `{{\(key)|...}}`."
                    )
                }
                i = close.upperBound
            } else {
                result.append(s[i])
                i = s.index(after: i)
            }
        }
        return result
    }
}

// MARK: - Parser

/// Hand-rolled indentation parser for the plugin schema. Reuses the flow
/// runner's scalar/mapping/step helpers so plugin steps and `guiport run` steps
/// share one grammar. Schema:
///
///   name: my-app
///   app: TextEdit
///   description: ...
///   actions:
///     - name: focus-and-type
///       description: ...
///       params: [text]
///       steps:
///         - activate: true
///         - assert: { frontmost: true }
///         - find: 'AXTextArea'
///         - type: '{{text}}'
///
enum PluginParser {
    static func parse(_ raw: String, path: String? = nil, defaultName: String) throws -> GuiportPlugin {
        let lines = raw.components(separatedBy: .newlines)
        var index = 0
        var name: String?
        var app: String?
        var description: String?
        var actions: [PluginAction] = []

        while index < lines.count {
            let rawLine = Runner.stripComment(lines[index])
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }

            // Only top-level (column 0) keys are structural here; deeper lines are
            // consumed by the action parser.
            guard Runner.leadingSpaces(rawLine) == 0 else { index += 1; continue }

            let (key, value) = try Runner.splitMapping(trimmed)
            switch key {
            case "name": name = scalarString(value); index += 1
            case "app": app = scalarString(value); index += 1
            case "description": description = scalarString(value); index += 1
            case "actions":
                index += 1
                actions = try parseActions(lines, &index)
            default:
                index += 1 // ignore unknown top-level keys for forward-compat
            }
        }

        guard !actions.isEmpty else {
            throw GuiportError(
                code: "plugin_parse",
                message: "plugin `\(name ?? defaultName)` declares no actions",
                hint: "Add an `actions:` list with at least one named action."
            )
        }
        return GuiportPlugin(name: name ?? defaultName, app: app, description: description, path: path, actions: actions)
    }

    private static func parseActions(_ lines: [String], _ index: inout Int) throws -> [PluginAction] {
        var actions: [PluginAction] = []
        var itemIndent = -1

        while index < lines.count {
            let rawLine = Runner.stripComment(lines[index])
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }
            let indent = Runner.leadingSpaces(rawLine)

            if itemIndent < 0 {
                if indent == 0 { break } // no indented action items
                itemIndent = indent
            }
            if indent < itemIndent { break }
            guard trimmed.hasPrefix("- ") else {
                throw GuiportError(code: "plugin_parse", message: "action must start with `- `, got `\(trimmed)`")
            }

            let contentIndent = indent + 2
            var name: String?
            var description: String?
            var params: [String] = []
            var steps: [Any] = []

            func absorb(_ mapping: String) throws {
                let (k, v) = try Runner.splitMapping(mapping)
                switch k {
                case "name": name = scalarString(v)
                case "description": description = scalarString(v)
                case "params": params = scalarList(v)
                default: break
                }
            }

            try absorb(String(trimmed.dropFirst(2)))
            index += 1

            while index < lines.count {
                let rl = Runner.stripComment(lines[index])
                let t = rl.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { index += 1; continue }
                if Runner.leadingSpaces(rl) < contentIndent { break }

                let (k, v) = try Runner.splitMapping(t)
                if k == "steps" && v.isEmpty {
                    index += 1
                    steps = try Runner.parseStepList(lines, &index, minIndent: contentIndent + 1)
                } else {
                    try absorb(t)
                    index += 1
                }
            }

            guard let actionName = name else {
                throw GuiportError(code: "plugin_parse", message: "action is missing `name`")
            }
            actions.append(PluginAction(name: actionName, description: description, params: params, steps: steps))
        }
        return actions
    }

    private static func scalarString(_ value: String) -> String? {
        Runner.parseScalar(value) as? String
    }

    private static func scalarList(_ value: String) -> [String] {
        switch Runner.parseScalar(value) {
        case let arr as [Any]: return arr.map { "\($0)" }
        case let s as String where !s.isEmpty: return [s]
        default: return []
        }
    }
}
