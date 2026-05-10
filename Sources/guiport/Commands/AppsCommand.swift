import ArgumentParser
import GuiportCore

struct AppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List running apps with windows."
    )

    @Flag(name: .long, help: "Include only apps that have at least one window.")
    var withWindows: Bool = false

    @OptionGroup var output: OutputOption

    func run() async throws {
        let apps = try AppRegistry.list(onlyWithWindows: withWindows)
        if output.json {
            try JSONOutput.print(apps, pretty: output.pretty)
        } else {
            for a in apps {
                let pid = a.pid.map { String($0) } ?? "-"
                print("\(a.name)\t\(a.bundleId ?? "-")\tpid=\(pid)\twindows=\(a.windowCount)")
            }
        }
    }
}
