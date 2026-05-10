import ArgumentParser
import GuiportCore

struct TypeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into the focused element."
    )

    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Per-character delay in milliseconds.")
    var delayMs: Int = 0

    @Argument(help: "Text to type.")
    var text: String

    func run() async throws {
        let result = try Adapter.current.type(text: text, perCharDelayMs: delayMs)
        try JSONOutput.print(result, pretty: output.pretty)
    }
}
