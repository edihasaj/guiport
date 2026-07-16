import ArgumentParser
import GuiportCore

/// Foreground a running app without relaunching it or synthesizing a click.
/// The same logic backs `guiport lifecycle activate`.
struct ActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Bring a running app to the front (no relaunch, no click)."
    )

    @Option(name: .long, help: "Target app: bundle id (com.x.y) or display name.")
    var app: String

    @OptionGroup var output: OutputOption

    func run() async throws {
        let result = try ActivateCommand.activate(app: app)
        try JSONOutput.print(result, pretty: output.pretty)
    }

    /// Resolve `app` to a running target and raise it. Shared by the top-level
    /// `activate` command and the `lifecycle activate` subcommand. Throws
    /// `app_not_found` when the app isn't running (via `resolveApp`).
    static func activate(app: String) throws -> ActivationResult {
        let target = try Adapter.current.resolveApp(name: app)
        return try Adapter.current.activate(target: target)
    }
}
