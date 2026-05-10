import ArgumentParser
import Foundation
import GuiportCore

struct AppOption: ParsableArguments {
    @Option(name: .long, help: "Target app name (localized name or bundle id).")
    var app: String?

    @Option(name: .long, help: "Target window title (substring match).")
    var window: String?
}

struct OutputOption: ParsableArguments {
    @Flag(name: .long, help: "Output JSON.")
    var json: Bool = false

    @Flag(name: .long, help: "Pretty-print JSON output.")
    var pretty: Bool = false
}

enum CLIExit {
    static func fail(_ err: GuiportError, json: Bool = false) -> Never {
        let stderr = FileHandle.standardError
        if json, let data = try? JSONEncoder().encode(err) {
            stderr.write(data)
            stderr.write(Data("\n".utf8))
        } else {
            stderr.write(Data("\(err)\n".utf8))
        }
        Foundation.exit(1)
    }
}
