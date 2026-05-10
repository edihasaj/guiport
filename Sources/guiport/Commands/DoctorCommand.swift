import ArgumentParser
import GuiportCore

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check permissions and environment readiness."
    )

    @OptionGroup var output: OutputOption

    func run() async throws {
        let report = Doctor.checkAll()
        if output.json {
            try JSONOutput.print(report, pretty: output.pretty)
        } else {
            print(report.humanReport())
        }
        if !report.ok { throw ExitCode(1) }
    }
}
