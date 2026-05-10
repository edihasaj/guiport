// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "guiport",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "guiport", targets: ["guiport"]),
        .library(name: "GuiportCore", targets: ["GuiportCore"]),
        .library(name: "GuiportMacAdapter", targets: ["GuiportMacAdapter"]),
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
        // Future: GuiportWindowsAdapter (UIA), GuiportLinuxAdapter (AT-SPI2 D-Bus).
        // .target(name: "GuiportWindowsAdapter", dependencies: ["GuiportCore"]),
        // .target(name: "GuiportLinuxAdapter",   dependencies: ["GuiportCore"]),

        .executableTarget(
            name: "guiport",
            dependencies: [
                "GuiportCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "GuiportMacAdapter", condition: .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "GuiportCoreTests",
            dependencies: ["GuiportCore"]
        ),
    ]
)
