import ArgumentParser
import GuiportCore

/// Friendly first-run command. Triggers TCC enrolment for Accessibility + Screen
/// Recording, opens System Settings to the right pane, and prints a clear "look
/// for `guiport` in the list, toggle it on" message.
struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "First-run setup — fire macOS permission prompts + open the right Settings panes."
    )

    @Flag(name: .long, help: "Output JSON (default: human-friendly text).")
    var json: Bool = false

    func run() async throws {
        let report = Doctor.fix()
        if json {
            try JSONOutput.print(report, pretty: true)
            if !report.ok { throw ExitCode(1) }
            return
        }

        print(report.humanReport())
        print("")
        print("→ System Settings was opened for any missing permissions.")
        print("→ Look for `guiport` in the list (or your terminal app, if it shows there instead) and toggle it on.")
        print("→ Then re-run `guiport doctor` to confirm.")
        if !report.ok { throw ExitCode(1) }
    }
}
