import XCTest
import Foundation

/// CLI-surface tests for `guiport plugin`. They write plugins into a temp dir
/// (passed via `--dir`) so they're hermetic and don't touch `~/.guiport`.
final class PluginCommandTests: XCTestCase {
    private var dir: String!

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "guiport-plugins-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plugin = """
        name: demo
        app: TextEdit
        description: A demo plugin.
        actions:
          - name: type-into
            description: Focus and type.
            params: [text]
            steps:
              - activate: true
              - assert:
                  frontmost: true
              - type: '{{text}}'
        """
        try plugin.write(toFile: dir + "/demo.yaml", atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    func testHelp() throws {
        let out = try CLI.run(["plugin", "--help"])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("list"))
        XCTAssertTrue(out.stdout.contains("run"))
    }

    func testListHuman() throws {
        let out = try CLI.run(["plugin", "list", "--dir", dir])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("demo"), out.stdout)
        XCTAssertTrue(out.stdout.contains("type-into"), out.stdout)
        XCTAssertTrue(out.stdout.contains("(text)"), out.stdout)
    }

    func testListJSON() throws {
        let out = try CLI.run(["plugin", "list", "--dir", dir, "--json"])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("\"name\":\"demo\""), out.stdout)
        XCTAssertTrue(out.stdout.contains("\"stepCount\":3"), out.stdout)
    }

    func testListEmptyDir() throws {
        let empty = NSTemporaryDirectory() + "guiport-empty-\(UUID().uuidString)"
        let out = try CLI.run(["plugin", "list", "--dir", empty])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.lowercased().contains("no plugins"), out.stdout)
    }

    func testRunMissingParamFails() throws {
        let out = try CLI.run(["plugin", "run", "demo", "type-into", "--dir", dir])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("missing_param"), out.stderr)
    }

    func testRunUnknownActionFails() throws {
        let out = try CLI.run(["plugin", "run", "demo", "ghost", "text=hi", "--dir", dir])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("action_not_found"), out.stderr)
    }

    func testRunUnknownPluginFails() throws {
        let out = try CLI.run(["plugin", "run", "ghost", "act", "text=hi", "--dir", dir])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("plugin_not_found"), out.stderr)
    }

    func testRunBadParamSyntaxFails() throws {
        let out = try CLI.run(["plugin", "run", "demo", "type-into", "textnovalue", "--dir", dir])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("key=value"), out.stderr)
    }

    /// End-to-end without depending on any app being present: overriding the app
    /// with a guaranteed-absent bundle id proves param substitution reaches the
    /// steps and the flow engine runs, failing cleanly at `activate`.
    func testRunReachesEngineWithAbsentApp() throws {
        let absent = "com.example.notrunning.\(UUID().uuidString)"
        let out = try CLI.run(["plugin", "run", "demo", "type-into", "text=hello",
                               "--dir", dir, "--app", absent])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("\"passed\":false"), out.stdout)
        XCTAssertTrue(out.stdout.contains("\"action\":\"activate\""), out.stdout)
        XCTAssertTrue(out.stdout.contains("app_not_found"), out.stdout)
    }
}
