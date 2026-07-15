import ArgumentParser
import Foundation
import GuiportCore

#if canImport(GuiportMacAdapter)
import GuiportMacAdapter
#endif

/// Runs the Aqua-session input daemon. Launched by the LaunchAgent (see
/// `guiport agent install`), not meant to be run by hand. Blocks forever,
/// posting forwarded synthetic events from within the GUI session.
struct AgentDaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-daemon",
        abstract: "Run the Aqua-session input daemon (used by the LaunchAgent).",
        shouldDisplay: false
    )

    func run() async throws {
        #if canImport(GuiportMacAdapter)
        setenv("GUIPORT_AGENT_DAEMON", "1", 1)
        try SessionBridge.runDaemon()
        #else
        throw GuiportError(code: "unsupported", message: "agent-daemon is macOS-only")
        #endif
    }
}
