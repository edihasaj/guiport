import ArgumentParser
import GuiportCore

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start an MCP server (stdio) that exposes guiport tools."
    )

    @Flag(name: .long, help: "Run as MCP server.")
    var mcp: Bool = false

    func run() async throws {
        guard mcp else {
            CLIExit.fail(.init(code: "missing_flag", message: "--mcp is required", hint: "guiport serve --mcp"))
        }
        try await MCPServer.runStdio()
    }
}
