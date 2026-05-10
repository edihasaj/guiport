import ArgumentParser
import GuiportCore

@main
struct Guiport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guiport",
        abstract: "Fast CLI/MCP control layer for desktop apps. Built for coding agents.",
        version: GuiportCore.Guiport.version,
        subcommands: [
            DoctorCommand.self,
            AppsCommand.self,
            ObserveCommand.self,
            TreeCommand.self,
            FindCommand.self,
            ClickCommand.self,
            TypeCommand.self,
            HotkeyCommand.self,
            ScreenshotCommand.self,
            RecordCommand.self,
            RunCommand.self,
            ServeCommand.self,
        ],
        defaultSubcommand: nil
    )
}
