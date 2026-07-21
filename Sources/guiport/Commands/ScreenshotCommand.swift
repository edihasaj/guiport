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

    /// Whether the capture should target a window rather than the whole screen.
    ///
    /// `--window` alone counts. It used to be ignored unless `--app` was also
    /// given, which silently captured the entire desktop — callers got a
    /// screenshot, just not of the window they asked for.
    static func targetsWindow(app: String?, window: String?) -> Bool {
        app?.isEmpty == false || window?.isEmpty == false
    }

    func run() async throws {
        let target: AppTarget? = Self.targetsWindow(app: app.app, window: app.window)
            ? try Adapter.current.resolveApp(name: app.app, windowTitle: app.window)
            : nil
        let path = outPath ?? Adapter.current.defaultScreenshotPath()
        let result = try Adapter.current.captureScreenshot(target: target, to: path)
        try JSONOutput.print(result, pretty: output.pretty)
    }
}
