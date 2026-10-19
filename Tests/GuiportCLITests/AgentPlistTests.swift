#if os(macOS)
import Foundation
import GuiportCore
import XCTest
@testable import guiport

final class AgentPlistTests: XCTestCase {
    func testLaunchAgentKeepsItsBundleIdentityAndDaemonArguments() throws {
        let plist = AgentCommand.launchAgentPlist(
            binaryPath: "/Applications/guiport.app/Contents/MacOS/guiport",
            owner: BackgroundAppOwner(
                bundleURL: URL(fileURLWithPath: "/Applications/guiport.app"),
                bundleIdentifier: "com.edihasaj.guiport"
            ),
            homePath: "/Users/test"
        )
        XCTAssertEqual(plist["AssociatedBundleIdentifiers"] as? [String], ["com.edihasaj.guiport"])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [
            "/Applications/guiport.app/Contents/MacOS/guiport", "agent-daemon"
        ])
        XCTAssertEqual(plist["Label"] as? String, "com.edihasaj.guiport.agent")
        XCTAssertEqual(plist["KeepAlive"] as? Bool, true)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    }

    func testPathsWithXMLCharactersRoundTripWithoutCorruption() throws {
        let executable = "/Applications/A&B <test>/guiport"
        let home = "/Users/A&B <test>"
        let plist = AgentCommand.launchAgentPlist(
            binaryPath: executable,
            owner: nil,
            homePath: home
        )
        XCTAssertNil(plist["AssociatedBundleIdentifiers"])
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let decoded = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(decoded["ProgramArguments"] as? [String], [executable, "agent-daemon"])
        XCTAssertEqual(decoded["StandardErrorPath"] as? String, home + "/.guiport/agent.log")
    }
}
#endif
