import ArgumentParser
import GuiportCore

struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an element by selector. Visual fallback kicks in automatically when needed."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Click button (left|right|center).")
    var button: String = "left"

    @Option(name: .long, help: "Click count.")
    var count: Int = 1

    @Flag(name: .long, help: "Use AXPress action instead of synthesizing a mouse event.")
    var press: Bool = false

    @Flag(name: .long, help: "Disable visual fallback — fail loud if AX selector misses.")
    var strict: Bool = false

    @Argument(help: "Selector, e.g. `button[name=\"Save\"]`.")
    var selector: String

    func run() async throws {
        let target = try Adapter.current.resolveApp(name: app.app, windowTitle: app.window)
        let mode: SmartClick.Mode = strict ? .strict : .auto
        do {
            let result = try SmartClick.click(
                selector: selector, target: target,
                button: button, count: count,
                useAXPress: press, mode: mode
            )
            try JSONOutput.print(result, pretty: output.pretty)
        } catch let e as GuiportError {
            CLIExit.fail(e)
        }
    }
}
