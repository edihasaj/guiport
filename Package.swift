// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "guiport",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "guiport", targets: ["guiport"]),
        .library(name: "GuiportCore", targets: ["GuiportCore"]),
        .library(name: "GuiportMacAdapter", targets: ["GuiportMacAdapter"]),
        .library(name: "GuiportWindowsAdapter", targets: ["GuiportWindowsAdapter"]),
        .library(name: "GuiportLinuxAdapter", targets: ["GuiportLinuxAdapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        // Platform-agnostic core: types, selector engine, runner, MCP server, adapter protocol.
        .target(
            name: "GuiportCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        // macOS adapter: Apple AX, CGEvent, Screenshots, Vision OCR, CGEventTap recorder.
        .target(
            name: "GuiportMacAdapter",
            dependencies: ["GuiportCore"]
        ),
        // Windows adapter: Win32 SendInput, GDI BitBlt, EnumWindows. UIA tree pending.
        // Sources are wrapped in `#if os(Windows)` so the target compiles to nothing on
        // non-Windows hosts — keeps macOS CI green.
        .target(
            name: "GuiportWindowsAdapter",
            dependencies: ["GuiportCore"]
        ),
        // Linux adapter: shell-out to xdotool/ydotool/wmctrl/grim/scrot for day-1 surface.
        // AT-SPI2 D-Bus tree is the upgrade path. Sources are #if os(Linux)-guarded.
        .target(
            name: "GuiportLinuxAdapter",
            dependencies: ["GuiportCore"]
        ),

        .executableTarget(
            name: "guiport",
            dependencies: [
                "GuiportCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "GuiportMacAdapter", condition: .when(platforms: [.macOS])),
                .target(name: "GuiportWindowsAdapter", condition: .when(platforms: [.windows])),
                .target(name: "GuiportLinuxAdapter", condition: .when(platforms: [.linux])),
            ],
            // Embed Info.plist so macOS TCC treats guiport as its own subject (Accessibility,
            // Screen Recording, Apple Events) regardless of the parent terminal. Without this,
            // CLI tools fall through to the parent's TCC grants — a separate grant per terminal.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "GuiportCoreTests",
            dependencies: ["GuiportCore"]
        ),
        // CLI integration tests — spawn the built `guiport` binary and
        // assert on stdout/stderr/exit code. Lives separate from
        // GuiportCoreTests because it shells out and is slower.
        .testTarget(
            name: "GuiportCLITests",
            dependencies: ["guiport"]
        ),
    ]
)
