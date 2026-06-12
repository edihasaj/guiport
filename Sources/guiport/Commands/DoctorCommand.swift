import ArgumentParser
import GuiportCore

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check permissions and environment readiness."
    )

    @OptionGroup var output: DualOutputOption

    @Flag(name: .long, help: "Fire missing permission prompts and open System Settings deep-links.")
    var fix: Bool = false

    func run() async throws {
        let report = fix ? Doctor.fix() : Doctor.checkAll()
        if output.json {
            try JSONOutput.print(report, pretty: output.pretty)
        } else {
            print(report.humanReport())
            if fix && !report.ok {
                print("")
                print("→ macOS prompts only show the dialog the first time guiport asks.")
                print("→ For repeat runs, toggle `guiport` in System Settings → Privacy & Security.")
                print("→ `doctor --fix` also registers ~/Applications/guiport.app so the list shows a real app entry.")
                print("→ After granting, re-run any guiport command.")
            }
        }
        if !report.ok { throw ExitCode(1) }
    }
}
