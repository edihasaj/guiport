#if os(macOS)
import Foundation
import XCTest
@testable import guiport

final class AgentPlistTests: XCTestCase {
    func testLaunchAgentKeepsItsBundleIdentityAndDaemonArguments() throws {
        let xml = AgentCommand.plistXML(
            executablePath: "/Applications/guiport.app/Contents/MacOS/guiport",
            homePath: "/Users/test")
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(
            from: Data(xml.utf8), format: nil) as? [String: Any])
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
        let xml = AgentCommand.plistXML(executablePath: executable, homePath: home)
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(
            from: Data(xml.utf8), format: nil) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [executable, "agent-daemon"])
        XCTAssertEqual(plist["StandardErrorPath"] as? String, home + "/.guiport/agent.log")
    }
}
#endif
