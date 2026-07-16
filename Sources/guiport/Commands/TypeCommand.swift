import ArgumentParser
import GuiportCore

// TypeMethod lives in GuiportCore (framework-free); the CLI teaches ArgumentParser
// how to parse it. RawRepresentable<String> gives the parsing for free.
extension TypeMethod: ExpressibleByArgument {}

struct TypeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into the focused element."
    )

    @OptionGroup var output: OutputOption

    @OptionGroup var guardFrontmost: FrontmostGuard

    @Option(name: .long, help: "Per-character delay in milliseconds (keystroke method).")
    var delayMs: Int = 0

    @Option(name: .long, help: "Injection method: auto (default), keystroke, or paste. auto pastes into web/Electron fields so no characters drop.")
    var method: TypeMethod = .auto

    @Argument(help: "Text to type.")
    var text: String

    func run() async throws {
        try guardFrontmost.enforce()
        let result = try Adapter.current.type(text: text, perCharDelayMs: delayMs, method: method)
        try JSONOutput.print(result, pretty: output.pretty)
    }
}
