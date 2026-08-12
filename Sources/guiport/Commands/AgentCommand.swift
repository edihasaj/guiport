import ArgumentParser
import Foundation
import GuiportCore

/// Manage the Aqua-session input agent — the LaunchAgent + daemon that lets a
/// background process (coding agent, SSH shell, CI runner) deliver clicks and
/// keystrokes to the on-screen GUI session.
///
/// Run `guiport agent install` ONCE from a Terminal in the logged-in GUI
/// session. After that, `guiport click/type/hotkey` invoked from any
/// background context auto-forward through the daemon and land on screen.
struct AgentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "Install/manage the Aqua-session input agent (lets background agents click on screen).",
        subcommands: [Install.self, Uninstall.self, Status.self, Restart.self]
    )

    static let label = "com.edihasaj.guiport.agent"
    static var plistPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var socketPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".guiport/agent.sock")
    }

    /// Path the LaunchAgent should exec.
    ///
    /// Prefer a *stable* `guiport` symlink on PATH (e.g. Homebrew's
    /// `bin/guiport`) that resolves to this running binary. Homebrew points that
    /// symlink into the versioned Cellar bundle and re-points it on every
    /// `brew upgrade`; baking the resolved versioned path into the plist instead
    /// leaves the LaunchAgent exec'ing a directory the next upgrade deletes.
    /// The exec'd binary is the same signed bundle either way, so the Screen
    /// Recording (TCC) identity is unchanged. Falls back to the resolved
    /// executable path for non-Homebrew installs with no such symlink.
    static func guiportPath() -> String {
        let resolved = Bundle.main.executableURL?.resolvingSymlinksInPath().path
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "guiport")
                .resolvingSymlinksInPath().path
        var candidates = ["/opt/homebrew/bin/guiport", "/usr/local/bin/guiport"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/guiport" }
        }
        let fm = FileManager.default
        for c in candidates where fm.fileExists(atPath: c) {
            // Only trust a symlink that actually resolves to this same binary.
            if URL(fileURLWithPath: c).resolvingSymlinksInPath().path == resolved { return c }
        }
        return resolved
    }

    /// Write the LaunchAgent plist for the current binary. Idempotent — both
    /// `install` and `restart` call it so an upgraded install re-points itself.
    static func writePlist() throws {
        let bin = guiportPath()
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(bin)</string>
            <string>agent-daemon</string>
          </array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>ProcessType</key><string>Interactive</string>
          <key>StandardErrorPath</key><string>\(NSHomeDirectory())/.guiport/agent.log</string>
        </dict>
        </plist>
        """
        let dir = (plistPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
    }

    static func currentUID() -> String {
        #if os(Windows)
        return "0"  // agent/LaunchAgent forwarding is macOS-only; UID is unused here.
        #else
        return String(getuid())
        #endif
    }

    /// Emit a JSON object (these management commands return mixed-type fields,
    /// so go through JSONSerialization rather than a typed Encodable).
    static func emit(_ obj: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: d, encoding: .utf8) {
            Swift.print(s)
        }
    }

    @discardableResult
    static func launchctl(_ args: [String]) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (1, "\(error)") }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }

    // MARK: install

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write the LaunchAgent and start the daemon in the GUI session. Run once from a Terminal."
        )

        func run() async throws {
            try AgentCommand.writePlist()

            let uid = AgentCommand.currentUID()
            // Reload cleanly: bootout any prior instance, then bootstrap fresh.
            AgentCommand.launchctl(["bootout", "gui/\(uid)/\(AgentCommand.label)"])
            let r = AgentCommand.launchctl(["bootstrap", "gui/\(uid)", AgentCommand.plistPath])

            var note = "installed LaunchAgent at \(AgentCommand.plistPath)"
            if r.code != 0 {
                // Common when run from a non-GUI session — the plist will still
                // auto-load on next login; surface guidance instead of failing.
                note += "; could not bootstrap now (run this from a Terminal in the logged-in GUI session, or it loads on next login). launchctl: \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))"
            } else {
                note += "; daemon started in GUI session"
            }
            AgentCommand.emit(["ok": true, "note": note])
        }
    }

    // MARK: uninstall

    struct Uninstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop the daemon and remove the LaunchAgent.")
        func run() async throws {
            let uid = AgentCommand.currentUID()
            AgentCommand.launchctl(["bootout", "gui/\(uid)/\(AgentCommand.label)"])
            try? FileManager.default.removeItem(atPath: AgentCommand.plistPath)
            try? FileManager.default.removeItem(atPath: AgentCommand.socketPath)
            AgentCommand.emit(["ok": true, "note": "agent uninstalled"])
        }
    }

    // MARK: status

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show whether the input agent is installed and running.")
        func run() async throws {
            let uid = AgentCommand.currentUID()
            let installed = FileManager.default.fileExists(atPath: AgentCommand.plistPath)
            let printed = AgentCommand.launchctl(["print", "gui/\(uid)/\(AgentCommand.label)"])
            let running = printed.code == 0
            let socket = FileManager.default.fileExists(atPath: AgentCommand.socketPath)
            AgentCommand.emit([
                "installed": installed,
                "running": running,
                "socket": socket,
                "plist": AgentCommand.plistPath,
            ])
        }
    }

    // MARK: restart

    struct Restart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restart the daemon (after a guiport upgrade).")
        func run() async throws {
            // Rewrite the plist first: after a `brew upgrade` an old install may
            // still point at a now-deleted versioned path, so restart re-points
            // it at the current binary before reloading.
            try AgentCommand.writePlist()
            let uid = AgentCommand.currentUID()
            AgentCommand.launchctl(["bootout", "gui/\(uid)/\(AgentCommand.label)"])
            let r = AgentCommand.launchctl(["bootstrap", "gui/\(uid)", AgentCommand.plistPath])
            AgentCommand.emit(["ok": r.code == 0, "note": r.out.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }
}
