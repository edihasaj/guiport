import ArgumentParser
import GuiportCore

struct FindCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Find elements matching a selector."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Maximum tree depth to search.")
    var maxDepth: Int = 30

    @Flag(name: .long, help: "Match all (default: only first).")
    var all: Bool = false

    @Argument(help: "Selector, e.g. `button[name=\"Save\"]`.")
    var selector: String

    func run() async throws {
        let target = try AppRegistry.resolve(name: app.app, windowTitle: app.window)
        let tree = try AXBridge.tree(target: target, maxDepth: maxDepth, includeHidden: false)
        let parsed = try Selector.parse(selector)
        let matches = parsed.match(tree)
        let result = all ? matches : Array(matches.prefix(1))
        try JSONOutput.print(result, pretty: output.pretty)
    }
}
