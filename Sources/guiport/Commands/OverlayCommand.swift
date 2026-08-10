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
            abstract: "Keep the animated controlling-glow overlay visible until interrupted."
        )

        @Option(name: .long, help: "Stop after this many seconds instead of running until interrupted.")
        var seconds: Double?

        mutating func validate() throws {
            if let seconds, seconds <= 0 {
                throw ValidationError("--seconds must be greater than zero")
            }
        }

        func run() async throws {
            #if canImport(GuiportMacAdapter)
            // The first ping auto-spawns the overlay daemon in this GUI session if
            // none is running; refreshing faster than the idle fade keeps it lit.
            let deadline = seconds.map { Date().addingTimeInterval($0) }
            while deadline.map({ Date() < $0 }) ?? true {
                SessionBridge.pingActivity(kind: "demo", point: nil)
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            if let seconds {
                OverlayCommand.emit(["ok": true, "shown_seconds": seconds])
            }
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
            let running = SessionBridge.isDaemonRunning()
            let available = true
            #else
            let running = false
            let available = false  // overlay is macOS-only
            #endif
            OverlayCommand.emit([
                // The overlay is available on demand (auto-spawns while guiport
                // drives the screen); `daemon_running` is the live state right now.
                "daemon_running": running,
                "overlay_available": available,
                "stopped": Cancellation.isCancelled(),
                "stop_reason": Cancellation.activeReason() as Any,
            ])
        }
    }
}
