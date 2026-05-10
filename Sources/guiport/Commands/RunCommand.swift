import ArgumentParser
import GuiportCore

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Replay a YAML test."
    )

    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Artifacts directory.")
    var artifacts: String = "artifacts"

    @Argument(help: "Path to YAML test file.")
    var path: String

    func run() async throws {
        let result = try await Runner.run(path: path, artifactsDir: artifacts)
        try JSONOutput.print(result, pretty: output.pretty || !output.json)
        if !result.passed { throw ExitCode(1) }
    }
}
