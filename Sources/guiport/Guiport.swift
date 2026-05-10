import ArgumentParser
import GuiportCore

#if canImport(GuiportMacAdapter)
import GuiportMacAdapter
#endif

#if canImport(GuiportWindowsAdapter)
import GuiportWindowsAdapter
#endif

#if canImport(GuiportLinuxAdapter)
import GuiportLinuxAdapter
#endif

@main
struct Guiport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guiport",
        abstract: "Fast CLI/MCP control layer for desktop apps. Built for coding agents.",
        version: GuiportCore.Guiport.version,
        subcommands: [
            InitCommand.self,
            DoctorCommand.self,
            AppsCommand.self,
            ObserveCommand.self,
            TreeCommand.self,
            FindCommand.self,
            ClickCommand.self,
            ClickAtCommand.self,
            FindTextCommand.self,
            ClickTextCommand.self,
            TypeCommand.self,
            HotkeyCommand.self,
            ScreenshotCommand.self,
            RecordCommand.self,
            RunCommand.self,
            ServeCommand.self,
            BenchCommand.self,
        ],
        defaultSubcommand: nil
    )

    /// Install the platform adapter once per process before any subcommand runs.
    static func main() async {
        installAdapter()
        await Self._mainAsync()
    }

    private static func installAdapter() {
        #if canImport(GuiportMacAdapter)
        Adapter.install(MacAdapter())
        #endif
        #if canImport(GuiportWindowsAdapter) && os(Windows)
        Adapter.install(WindowsAdapter())
        #endif
        #if canImport(GuiportLinuxAdapter) && os(Linux)
        Adapter.install(LinuxAdapter())
        #endif
    }

    /// Re-implement ArgumentParser's async entry point so we can hook adapter install above.
    private static func _mainAsync() async {
        do {
            var cmd = try parseAsRoot(nil)
            if var asyncCmd = cmd as? AsyncParsableCommand {
                try await asyncCmd.run()
            } else {
                try cmd.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}
