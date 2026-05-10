import ArgumentParser
import GuiportCore

struct ClickAtCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click-at",
        abstract: "Click at raw screen coordinates (vision/OCR fallback)."
    )

    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Click button (left|right|center).")
    var button: String = "left"

    @Option(name: .long, help: "Click count.")
    var count: Int = 1

    @Argument(help: "X coordinate (screen pixels).")
    var x: Double

    @Argument(help: "Y coordinate (screen pixels).")
    var y: Double

    func run() async throws {
        let result = try Adapter.current.clickAt(x: x, y: y, button: button, count: count)
        try JSONOutput.print(result, pretty: output.pretty)
    }
}
