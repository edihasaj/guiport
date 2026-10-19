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
    /// Bundle identity of the `guiport` executable (the `CFBundleIdentifier` in
    /// `Resources/Info.plist`, embedded in the binary at link time).
    static let bundleIdentifier = "com.edihasaj.guiport"
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

    /// Render the LaunchAgent plist XML.
    ///
    /// `AssociatedBundleIdentifiers` is the key that makes the job show up in
    /// System Settings → General → Login Items *as guiport* rather than as a
    /// nameless background item: per the `launchd.plist` man page, it "indicates
    /// which bundles are associated with this job in the System Settings Login
    /// Items UI", and a legacy plist installed by an app "should include this key
    /// with a value of the app's bundle identifier". Without it launchd has no
    /// bundle to attribute the job to, so the entry is anonymous and the user
    /// cannot tell what it belongs to — or toggle it off.
    ///
    /// Pure — no `NSHomeDirectory()`, no filesystem access, no `launchctl` — so
    /// tests can parse the result with `PropertyListSerialization` instead of
    /// installing an agent. `writePlist()` is the only writer.
    static func plistXML(executablePath: String, homePath: String) -> String {
        let bin = xmlEscape(executablePath)
        let logPath = xmlEscape((homePath as NSString).appendingPathComponent(".guiport/agent.log"))
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(xmlEscape(label))</string>
          <key>AssociatedBundleIdentifiers</key>
          <array>
            <string>\(xmlEscape(bundleIdentifier))</string>
          </array>
          <key>ProgramArguments</key>
          <array>
            <string>\(bin)</string>
            <string>agent-daemon</string>
          </array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>ProcessType</key><string>Interactive</string>
          <key>StandardErrorPath</key><string>\(logPath)</string>
        </dict>
        </plist>
        """
    }

    /// Escape a value for plist XML. Home and install paths are plain POSIX
    /// paths, but a username may legitimately contain `&` — unescaped, that
    /// produces a plist launchd refuses to parse at all.
    static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Write the LaunchAgent plist for the current binary. Idempotent — both
    /// `install` and `restart` call it so an upgraded install re-points itself.
    static func writePlist() throws {
        let plist = plistXML(executablePath: guiportPath(), homePath: NSHomeDirectory())
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

    /// Reload the LaunchAgent and confirm the daemon is running.
    ///
    /// `launchctl bootout` returns before launchd has finished removing the
    /// service, so an immediate `bootstrap` often fails with "Bootstrap failed:
    /// 5: Input/output error" and leaves no daemon at all. That is what made the
    /// first `agent restart` after a `brew upgrade` report success while input
    /// commands then failed with "Aqua input agent not reachable".
    static func reload() -> (ok: Bool, running: Bool, note: String) {
        let uid = currentUID()
        let service = "gui/\(uid)/\(label)"
        launchctl(["bootout", service])
        _ = waitFor(seconds: 5) { launchctl(["print", service]).code != 0 }
        var result = launchctl(["bootstrap", "gui/\(uid)", plistPath])
        var attempts = 1
        while result.code != 0, attempts < 5 {
            Thread.sleep(forTimeInterval: 0.5)
            result = launchctl(["bootstrap", "gui/\(uid)", plistPath])
            attempts += 1
        }
        let running = result.code == 0 && waitFor(seconds: 5) {
            launchctl(["print", service]).out.contains("state = running")
        }
        let note = result.code == 0
            ? (running ? "daemon running" : "daemon loaded but not running yet; check ~/.guiport/agent.log")
            : "launchctl bootstrap failed after \(attempts) attempts: \(result.out.trimmingCharacters(in: .whitespacesAndNewlines))"
        return (result.code == 0, running, note)
    }

    static func waitFor(seconds: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return condition()
    }

    // MARK: install

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write the LaunchAgent and start the daemon in the GUI session. Run once from a Terminal."
        )

        func run() async throws {
            try AgentCommand.writePlist()

            // Reload cleanly: bootout any prior instance, then bootstrap fresh.
            let r = AgentCommand.reload()

            var note = "installed LaunchAgent at \(AgentCommand.plistPath)"
            if !r.ok {
                // Common when run from a non-GUI session — the plist will still
                // auto-load on next login; surface guidance instead of failing.
                note += "; could not bootstrap now (run this from a Terminal in the logged-in GUI session, or it loads on next login). \(r.note)"
            } else {
                note += "; \(r.note)"
            }
            AgentCommand.emit(["ok": true, "running": r.running, "note": note])
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
            let r = AgentCommand.reload()
            AgentCommand.emit(["ok": r.ok && r.running, "running": r.running, "note": r.note])
        }
    }
}
