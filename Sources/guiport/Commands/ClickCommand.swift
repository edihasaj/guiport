import ArgumentParser
import GuiportCore

struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an element matched by selector."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Click button (left|right|center).")
    var button: String = "left"

    @Option(name: .long, help: "Click count.")
    var count: Int = 1

    @Flag(name: .long, help: "Use AXPress action instead of synthesizing a mouse event.")
    var press: Bool = false

    @Argument(help: "Selector, e.g. `button[name=\"Save\"]`.")
    var selector: String

    func run() async throws {
        let target = try AppRegistry.resolve(name: app.app, windowTitle: app.window)
        let tree = try AXBridge.tree(target: target, maxDepth: 30, includeHidden: false)
        let parsed = try Selector.parse(selector)
        guard let match = parsed.match(tree).first else {
            CLIExit.fail(.init(code: "no_match", message: "selector matched no element", hint: "try `guiport find` to inspect"), json: output.json)
        }
        let result = try Input.click(match, app: target, button: button, count: count, useAXPress: press)
        try JSONOutput.print(result, pretty: output.pretty || !output.json)
    }
}
