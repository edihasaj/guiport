import ArgumentParser
import GuiportCore

struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an element matched by selector. Optional OCR fallback for sparse-AX apps."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Click button (left|right|center).")
    var button: String = "left"

    @Option(name: .long, help: "Click count.")
    var count: Int = 1

    @Flag(name: .long, help: "Use AXPress action instead of synthesizing a mouse event.")
    var press: Bool = false

    @Option(name: .long, help: "Fallback strategy if AX selector misses (none|ocr).")
    var fallback: String = "none"

    @Argument(help: "Selector, e.g. `button[name=\"Save\"]`.")
    var selector: String

    func run() async throws {
        let target = try AppRegistry.resolve(name: app.app, windowTitle: app.window)
        let fb = SmartClick.Fallback(rawValue: fallback.lowercased()) ?? .none
        do {
            let result = try SmartClick.click(
                selector: selector, target: target,
                button: button, count: count,
                useAXPress: press, fallback: fb
            )
            try JSONOutput.print(result, pretty: output.pretty)
        } catch let e as GuiportError {
            CLIExit.fail(e)
        }
    }
}
