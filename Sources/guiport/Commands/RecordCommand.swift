import ArgumentParser
import GuiportCore

struct RecordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Record a session into a YAML test file (interactive)."
    )

    @OptionGroup var app: AppOption

    @Argument(help: "Output YAML path.")
    var path: String

    func run() async throws {
        let target = try AppRegistry.resolve(name: app.app, windowTitle: app.window)
        try Recorder.record(target: target, to: path)
    }
}
