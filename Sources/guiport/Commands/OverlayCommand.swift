import ArgumentParser
import Foundation
import GuiportCore

#if canImport(GuiportMacAdapter)
import GuiportMacAdapter
#endif

/// `guiport overlay …` — inspect and demo the "GuiPort is controlling your
/// screen" indicator that the Aqua agent-daemon paints while guiport drives the
/// machine (amber glow border, cursor halo, Stop pill).
struct OverlayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overlay",
        abstract: "Show/inspect the on-screen \"controlling\" glow indicator.",
        subcommands: [Demo.self, Status.self]
    )

    static func emit(_ obj: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: d, encoding: .utf8) { print(s) }
    }

    // MARK: demo

    /// Pulse activity at the daemon so the overlay appears — a way to see and
    /// verify the glow without driving a real app.
    struct Demo: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Flash the controlling-glow overlay for a few seconds (needs `guiport agent install`)."
        )

        @Option(name: .long, help: "How long to keep the overlay lit.")
        var seconds: Double = 4

        func run() async throws {
            #if canImport(GuiportMacAdapter)
            let socket = FileManager.default.fileExists(atPath: SessionBridge.socketPath)
            guard socket else {
                throw GuiportError(
                    code: "overlay_no_daemon",
                    message: "the Aqua agent-daemon isn't running, so there's nothing to show the overlay",
                    hint: "install it once from a Terminal in the logged-in GUI session: `guiport agent install`")
            }
            // Refresh faster than the daemon's idle fade so the glow stays lit.
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                SessionBridge.pingActivity(kind: "mouse", point: nil)
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            OverlayCommand.emit(["ok": true, "shown_seconds": seconds])
            #else
            throw GuiportError(code: "unsupported", message: "the overlay is macOS-only")
            #endif
        }
    }

    // MARK: status

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Report whether the overlay is available and whether guiport is currently stopped.")

        func run() async throws {
            #if canImport(GuiportMacAdapter)
            let socket = FileManager.default.fileExists(atPath: SessionBridge.socketPath)
            #else
            let socket = false
            #endif
            OverlayCommand.emit([
                "daemon_socket": socket,
                "overlay_available": socket,
                "stopped": Cancellation.isCancelled(),
                "stop_reason": Cancellation.activeReason() as Any,
            ])
        }
    }
}
