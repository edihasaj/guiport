import ArgumentParser
import GuiportCore

/// Discover and run user plugins — named, reusable automations built from the
/// public primitives. Core ships no app-specific logic; plugins live in
/// `~/.guiport/plugins/*.{yaml,yml}` (override with `GUIPORT_PLUGINS_DIR` or
/// `--dir`).
struct PluginCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugin",
        abstract: "List and run user plugins (reusable app automations).",
        subcommands: [List.self, Run.self]
    )

    // MARK: - plugin list

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List available plugins and their actions."
        )

        @Option(name: .long, help: "Plugins directory (default: $GUIPORT_PLUGINS_DIR or ~/.guiport/plugins).")
        var dir: String?

        @OptionGroup var output: DualOutputOption

        func run() async throws {
            let plugins = PluginStore.list(dir: dir)

            if output.json {
                try JSONOutput.print(plugins, pretty: output.pretty)
                return
            }

            guard !plugins.isEmpty else {
                let d = dir ?? PluginStore.defaultDir()
                print("No plugins found in \(d).")
                print("Drop a .yaml plugin there (see examples/plugins/) or set GUIPORT_PLUGINS_DIR.")
                return
            }

            for p in plugins {
                let app = p.app.map { " → \($0)" } ?? ""
                print("\(p.name)\(app)")
                if let d = p.description, !d.isEmpty { print("  \(d)") }
                for a in p.actions {
                    let params = a.params.isEmpty ? "" : " (\(a.params.joined(separator: ", ")))"
                    let desc = a.description.map { " — \($0)" } ?? ""
                    print("  • \(a.name)\(params)\(desc)")
                }
            }
        }
    }

    // MARK: - plugin run

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Run a plugin action: guiport plugin run <plugin> <action> [key=value ...]"
        )

        @Argument(help: "Plugin name (filename stem or declared name) or path to a .yaml file.")
        var plugin: String

        @Argument(help: "Action to run.")
        var action: String

        @Argument(help: "Action params as key=value pairs.")
        var params: [String] = []

        @Option(name: .long, help: "Plugins directory (default: $GUIPORT_PLUGINS_DIR or ~/.guiport/plugins).")
        var dir: String?

        @Option(name: .long, help: "Override the plugin's target app.")
        var app: String?

        @Option(name: .long, help: "Artifacts directory for failure captures.")
        var artifacts: String = "artifacts"

        @Option(name: .long, help: "Default per-step timeout in ms.")
        var timeoutMs: Int = 5000

        @OptionGroup var output: OutputOption

        func run() async throws {
            let args = try Self.parseArgs(params)
            let loaded = try PluginStore.load(name: plugin, dir: dir)
            let result = try await PluginStore.run(
                plugin: loaded, action: action, args: args,
                appOverride: app, artifactsDir: artifacts, timeoutMs: timeoutMs
            )
            try JSONOutput.print(result, pretty: output.pretty)
            if !result.passed { throw ExitCode(1) }
        }

        /// Parse `key=value` pairs. Empty values are allowed (`note=`).
        static func parseArgs(_ pairs: [String]) throws -> [String: String] {
            var out: [String: String] = [:]
            for pair in pairs {
                guard let eq = pair.firstIndex(of: "=") else {
                    throw ValidationError("param `\(pair)` must be key=value")
                }
                let key = String(pair[..<eq])
                guard !key.isEmpty else { throw ValidationError("param `\(pair)` has an empty key") }
                out[key] = String(pair[pair.index(after: eq)...])
            }
            return out
        }
    }
}
