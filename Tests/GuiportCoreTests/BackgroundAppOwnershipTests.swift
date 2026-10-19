import Foundation
import XCTest
@testable import GuiportCore

final class BackgroundAppOwnershipTests: XCTestCase {
    private let identifier = "com.edihasaj.guiport"

    func testDiscoversOnlyTheBundleThatContainsTheExecutable() throws {
        try withFixtureApp { bundle, executable in
            let owner = BackgroundAppOwnership.discover(
                executableURL: executable,
                expectedBundleIdentifier: identifier
            )
            XCTAssertEqual(owner?.bundleURL.standardizedFileURL, bundle.standardizedFileURL)
            XCTAssertEqual(owner?.bundleIdentifier, identifier)
        }
    }

    func testDiscoversAnExecutablePassedThroughASymlink() throws {
        try withFixtureApp { bundle, executable in
            let symlink = bundle.deletingLastPathComponent().appendingPathComponent("guiport-link")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: executable)
            let owner = BackgroundAppOwnership.discover(
                executableURL: symlink,
                expectedBundleIdentifier: identifier
            )
            XCTAssertEqual(owner?.bundleURL.standardizedFileURL, bundle.standardizedFileURL)
        }
    }

    func testRejectsMissingAndMalformedBundleLayoutAndMetadata() throws {
        try withFixtureApp { bundle, executable in
            XCTAssertNil(BackgroundAppOwnership.discover(
                executableURL: bundle.appendingPathComponent("Contents/Resources/guiport"),
                expectedBundleIdentifier: identifier
            ))

            let info = bundle.appendingPathComponent("Contents/Info.plist")
            try FileManager.default.removeItem(at: info)
            XCTAssertNil(BackgroundAppOwnership.discover(
                executableURL: executable,
                expectedBundleIdentifier: identifier
            ))

            try plist(["CFBundleIdentifier": identifier, "CFBundleExecutable": "other"])
                .write(to: info, options: .atomic)
            XCTAssertNil(BackgroundAppOwnership.discover(
                executableURL: executable,
                expectedBundleIdentifier: identifier
            ))
        }
    }

    func testRejectsForeignBundleIdentifier() throws {
        try withFixtureApp(identifier: "com.example.other") { _, executable in
            XCTAssertNil(BackgroundAppOwnership.discover(
                executableURL: executable,
                expectedBundleIdentifier: identifier
            ))
        }
    }

    func testRequiresSuccessfulSignatureAndLaunchServicesRegistration() throws {
        try withFixtureApp { _, executable in
            var registered = false
            XCTAssertNil(BackgroundAppOwnership.verifiedAndRegistered(
                executableURL: executable,
                expectedBundleIdentifier: identifier,
                verifySignature: { _ in false },
                registerWithLaunchServices: { _ in
                    registered = true
                    return true
                }
            ))
            XCTAssertFalse(registered)

            var registrationAttempted = false
            XCTAssertNil(BackgroundAppOwnership.verifiedAndRegistered(
                executableURL: executable,
                expectedBundleIdentifier: identifier,
                verifySignature: { _ in true },
                registerWithLaunchServices: { _ in
                    registrationAttempted = true
                    return false
                }
            ))
            XCTAssertTrue(registrationAttempted)
            let owner = BackgroundAppOwnership.verifiedAndRegistered(
                executableURL: executable,
                expectedBundleIdentifier: identifier,
                verifySignature: { _ in true },
                registerWithLaunchServices: { _ in true }
            )
            XCTAssertEqual(owner?.bundleIdentifier, identifier)
        }
    }

    func testAssociationIsAbsentWithoutOwnerAndStableAcrossRepeatedGeneration() throws {
        let base = [
            "Label": "com.edihasaj.guiport.agent",
            "ProgramArguments": ["/Applications/Guiport & Tools/guiport", "agent-daemon"],
        ] as [String: Any]
        XCTAssertNil(BackgroundAppOwnership.associating(base, with: nil)["AssociatedBundleIdentifiers"])

        let owner = BackgroundAppOwner(
            bundleURL: URL(fileURLWithPath: "/Applications/Guiport.app"),
            bundleIdentifier: identifier
        )
        let once = BackgroundAppOwnership.associating(base, with: owner)
        let twice = BackgroundAppOwnership.associating(once, with: owner)
        XCTAssertEqual(twice["AssociatedBundleIdentifiers"] as? [String], [identifier])

        let xml = try PropertyListSerialization.data(fromPropertyList: twice, format: .xml, options: 0)
        let decoded = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(
            decoded["ProgramArguments"] as? [String],
            ["/Applications/Guiport & Tools/guiport", "agent-daemon"]
        )
    }

    private func withFixtureApp(
        identifier: String? = nil,
        body: (URL, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Guiport.app", isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("guiport")
        try Data().write(to: executable)
        try plist([
            "CFBundleIdentifier": identifier ?? self.identifier,
            "CFBundleExecutable": "guiport",
        ]).write(
            to: bundle.appendingPathComponent("Contents/Info.plist"),
            options: .atomic
        )
        try body(bundle, executable)
    }

    private func plist(_ value: [String: String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }
}
