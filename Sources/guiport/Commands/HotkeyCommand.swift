import ArgumentParser
import GuiportCore

struct HotkeyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hotkey",
        abstract: "Send a hotkey combo, e.g. `cmd+shift+t`."
    )

    @OptionGroup var output: OutputOption

    @Argument(help: "Combo, e.g. `cmd+s`, `cmd+shift+t`, `escape`.")
    var combo: String

    func run() async throws {
        let result = try Input.hotkey(combo)
        try JSONOutput.print(result, pretty: output.pretty)
    }
}
