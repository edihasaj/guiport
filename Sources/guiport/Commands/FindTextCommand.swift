import ArgumentParser
import GuiportCore

struct FindTextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find-text",
        abstract: "Find on-screen text via Apple Vision OCR (accessibility-free fallback)."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Flag(name: .long, help: "Require exact (case-insensitive) match.")
    var exact: Bool = false

    @Option(name: .long, help: "Max matches.")
    var limit: Int = 10

    @Argument(help: "Text to search for (substring by default).")
    var query: String

    func run() async throws {
        let target: AppTarget? = app.app != nil
            ? try AppRegistry.resolve(name: app.app, windowTitle: app.window)
            : nil
        let matches = try OCR.findText(in: target, query: query, exact: exact, limit: limit)
        try JSONOutput.print(matches, pretty: output.pretty)
    }
}
