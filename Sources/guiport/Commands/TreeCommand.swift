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
        let target = try Adapter.current.resolveApp(name: app.app, windowTitle: app.window)
        let tree = try Adapter.current.tree(target: target, maxDepth: maxDepth, includeHidden: includeHidden)
        try JSONOutput.print(tree, pretty: output.pretty)
    }
}
