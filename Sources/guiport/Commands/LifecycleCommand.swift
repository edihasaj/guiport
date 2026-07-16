import ArgumentParser
import Foundation
import GuiportCore
#if canImport(AppKit)
import AppKit
#endif

/// Launch / quit / restart an app from one place. Replaces the
/// `open(1)` + `osascript -e 'tell application X to quit'` + `pkill` dance.
struct LifecycleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lifecycle",
        abstract: "Launch, quit, kill, or restart an app.",
        subcommands: [Launch.self, Activate.self, Quit.self, Kill.self, Restart.self]
    )

    struct Common: ParsableArguments {
        @Option(name: .long, help: "Target app: bundle id (com.x.y) or display name. For 'launch' you can also pass a path to a .app.")
        var app: String

        @Option(name: .long, help: "Seconds to wait for the state change. Default 6.")
        var timeout: Double = 6
    }

    struct LaunchResult: Encodable {
        let action = "launch"
        let app: String
        let pid: Int32?
        let bundleId: String?
        let launched: Bool
    }

    struct ActivateResult: Encodable {
        let action = "activate"
        let app: String
        let pid: Int32
        let bundleId: String?
        /// True when the app is frontmost after the call (the verifiable outcome).
        let active: Bool
        /// True when it was already frontmost, so no activation was needed.
        let alreadyFrontmost: Bool
    }

    struct QuitResult: Encodable {
        let action: String
        let app: String
        let pids: [Int32]
        let stopped: Bool
    }

    // MARK: - launch

    struct Launch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "launch",
            abstract: "Launch an app (no-op if already running)."
        )
        @OptionGroup var common: Common
        @OptionGroup var output: OutputOption

        func run() async throws {
            let r = try Lifecycle.launch(app: common.app, timeout: common.timeout)
            try JSONOutput.print(r, pretty: output.pretty)
        }
    }

    // MARK: - activate (foreground without relaunch)

    struct Activate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "activate",
            abstract: "Foreground a running app without relaunching or clicking."
        )
        @OptionGroup var common: Common
        @OptionGroup var output: OutputOption

        func run() async throws {
            let r = try Lifecycle.activate(app: common.app, timeout: common.timeout)
            try JSONOutput.print(r, pretty: output.pretty)
        }
    }

    // MARK: - quit (graceful)

    struct Quit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "quit",
            abstract: "Politely quit an app (sends terminate)."
        )
        @OptionGroup var common: Common
        @OptionGroup var output: OutputOption

        func run() async throws {
            let r = try Lifecycle.quit(app: common.app, force: false, timeout: common.timeout)
            try JSONOutput.print(r, pretty: output.pretty)
        }
    }

    // MARK: - kill (force)

    struct Kill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "kill",
            abstract: "Force-quit an app (SIGKILL fallback)."
        )
        @OptionGroup var common: Common
        @OptionGroup var output: OutputOption

        func run() async throws {
            let r = try Lifecycle.quit(app: common.app, force: true, timeout: common.timeout)
            try JSONOutput.print(r, pretty: output.pretty)
        }
    }

    // MARK: - restart

    struct Restart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "restart",
            abstract: "Quit then relaunch an app."
        )
        @OptionGroup var common: Common
        @OptionGroup var output: OutputOption

        func run() async throws {
            _ = try Lifecycle.quit(app: common.app, force: false, timeout: common.timeout)
            let r = try Lifecycle.launch(app: common.app, timeout: common.timeout)
            try JSONOutput.print(r, pretty: output.pretty)
        }
    }
}
