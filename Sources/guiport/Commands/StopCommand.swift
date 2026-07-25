import ArgumentParser
import Foundation
import GuiportCore

/// `guiport stop` — raise the Stop signal so the next click/type/hotkey (local or
/// forwarded through the agent) aborts. This is the same signal the on-screen
/// overlay's Stop button and the ESC key raise; exposed on the CLI so scripts and
/// tests can trigger it too.
struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop guiport: abort the next on-screen action (same as the overlay Stop / ESC)."
    )

    @Option(name: .long, help: "Reason recorded with the stop.")
    var reason: String = "guiport stop"

    func run() async throws {
        Cancellation.requestCancel(reason: reason)
        emit(["ok": true, "stopped": true, "reason": reason,
              "note": "guiport will abort on-screen actions until it clears; run `guiport resume` to re-enable now."])
    }

    private func emit(_ obj: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: d, encoding: .utf8) { print(s) }
    }
}

/// `guiport resume` — clear a Stop immediately so guiport can act again.
struct ResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Clear a Stop so guiport can drive the screen again."
    )

    func run() async throws {
        Cancellation.clear()
        if let d = try? JSONSerialization.data(
            withJSONObject: ["ok": true, "stopped": false, "note": "guiport re-enabled"],
            options: [.prettyPrinted, .sortedKeys]), let s = String(data: d, encoding: .utf8) {
            print(s)
        }
    }
}
