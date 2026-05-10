import ArgumentParser
import GuiportCore
import Foundation

struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a screenshot of an app window or the full screen."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Option(name: [.customShort("o"), .customLong("out")], help: "Output path. Defaults to artifacts/.")
    var outPath: String?

    func run() async throws {
        let target: AppTarget? = (app.app != nil) ? try Adapter.current.resolveApp(name: app.app, windowTitle: app.window) : nil
        let path = outPath ?? Adapter.current.defaultScreenshotPath()
        let result = try Adapter.current.captureScreenshot(target: target, to: path)
        try JSONOutput.print(result, pretty: output.pretty)
    }
}
