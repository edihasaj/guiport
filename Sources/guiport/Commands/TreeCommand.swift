import ArgumentParser
import GuiportCore

struct TreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tree",
        abstract: "Dump the accessibility tree of the focused window."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Maximum tree depth.")
    var maxDepth: Int = 30

    @Flag(name: .long, help: "Include offscreen / invisible elements.")
    var includeHidden: Bool = false

    func run() async throws {
        let target = try AppRegistry.resolve(name: app.app, windowTitle: app.window)
        let tree = try AXBridge.tree(target: target, maxDepth: maxDepth, includeHidden: includeHidden)
        if output.json || true {
            try JSONOutput.print(tree, pretty: output.pretty || !output.json)
        }
    }
}
