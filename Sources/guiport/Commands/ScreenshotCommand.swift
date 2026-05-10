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
        let target: AppTarget? = (app.app != nil) ? try AppRegistry.resolve(name: app.app, windowTitle: app.window) : nil
        let path = outPath ?? Screenshot.defaultPath()
        let result = try Screenshot.capture(target: target, to: path)
        try JSONOutput.print(result, pretty: output.pretty)
    }
}
