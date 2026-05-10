// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "guiport",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "guiport", targets: ["guiport"]),
        .library(name: "GuiportCore", targets: ["GuiportCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "GuiportCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "guiport",
            dependencies: [
                "GuiportCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "GuiportCoreTests",
            dependencies: ["GuiportCore"]
        ),
    ]
)
