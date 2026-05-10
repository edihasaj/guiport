import ArgumentParser
import GuiportCore

struct ClickTextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click-text",
        abstract: "OCR-find text and click its center (Vision fallback for canvas/Electron)."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Flag(name: .long, help: "Require exact (case-insensitive) match.")
    var exact: Bool = false

    @Option(name: .long, help: "Click button (left|right|center).")
    var button: String = "left"

    @Option(name: .long, help: "Click count.")
    var count: Int = 1

    @Argument(help: "Text to click on (substring by default).")
    var query: String

    func run() async throws {
        let target: AppTarget? = app.app != nil
            ? try Adapter.current.resolveApp(name: app.app, windowTitle: app.window)
            : nil
        let matches = try Adapter.current.findText(in: target, query: query, exact: exact, limit: 1)
        guard let m = matches.first else {
            CLIExit.fail(.init(code: "ocr_no_match",
                               message: "no on-screen text matched \"\(query)\"",
                               hint: "try `guiport find-text` to inspect what Vision sees"))
        }
        _ = try Adapter.current.clickAt(x: m.centerX, y: m.centerY, button: button, count: count)
        try JSONOutput.print(m, pretty: output.pretty)
    }
}
