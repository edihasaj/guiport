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

    /// Resolve the on-disk path of the running guiport binary so the LaunchAgent
    /// invokes the same build.
    static func guiportPath() -> String {
        if let p = Bundle.main.executableURL?.resolvingSymlinksInPath().path { return p }
        let argv0 = CommandLine.arguments.first ?? "guiport"
        return URL(fileURLWithPath: argv0).resolvingSymlinksInPath().path
    }

    static func currentUID() -> String { String(getuid()) }

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
            let bin = AgentCommand.guiportPath()
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key><string>\(AgentCommand.label)</string>
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
            let dir = (AgentCommand.plistPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try plist.write(toFile: AgentCommand.plistPath, atomically: true, encoding: .utf8)

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
            let uid = AgentCommand.currentUID()
            AgentCommand.launchctl(["bootout", "gui/\(uid)/\(AgentCommand.label)"])
            let r = AgentCommand.launchctl(["bootstrap", "gui/\(uid)", AgentCommand.plistPath])
            AgentCommand.emit(["ok": r.code == 0, "note": r.out.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }
}
