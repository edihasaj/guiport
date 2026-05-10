import ArgumentParser
import Foundation
import GuiportCore

struct AppOption: ParsableArguments {
    @Option(name: .long, help: "Target app name (localized name or bundle id).")
    var app: String?

    @Option(name: .long, help: "Target window title (substring match).")
    var window: String?
}

/// Output is always JSON for agent-friendly commands. `--pretty` indents for humans.
struct OutputOption: ParsableArguments {
    @Flag(name: .long, help: "Pretty-print JSON output (default: compact for piping).")
    var pretty: Bool = false
}

/// For commands with a non-JSON human mode (apps, doctor). `--json` switches to JSON.
struct DualOutputOption: ParsableArguments {
    @Flag(name: .long, help: "Output JSON instead of human-friendly text.")
    var json: Bool = false

    @Flag(name: .long, help: "Pretty-print when --json is set.")
    var pretty: Bool = false
}

enum CLIExit {
    static func fail(_ err: GuiportError) -> Never {
        let stderr = FileHandle.standardError
        if let data = try? JSONEncoder().encode(err) {
            stderr.write(data)
            stderr.write(Data("\n".utf8))
        } else {
            stderr.write(Data("\(err)\n".utf8))
        }
        Foundation.exit(1)
    }
}
