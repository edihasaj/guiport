import ArgumentParser
import GuiportCore

struct ObserveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "observe",
        abstract: "Summarize focused window of an app."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    func run() async throws {
        let target = try AppRegistry.resolve(name: app.app, windowTitle: app.window)
        let summary = try AXBridge.observe(target: target)
        if output.json {
            try JSONOutput.print(summary, pretty: output.pretty)
        } else {
            print("app: \(summary.app.name) [\(summary.app.bundleId ?? "-")]")
            print("window: \(summary.window?.title ?? "-")")
            if let bounds = summary.window?.bounds {
                print("bounds: \(bounds.x),\(bounds.y) \(bounds.width)x\(bounds.height)")
            }
            print("focused: \(summary.focusedRole ?? "-") / \(summary.focusedName ?? "-")")
        }
    }
}
