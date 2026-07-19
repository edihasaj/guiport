import XCTest
@testable import GuiportCore

/// Unit tests for the plugin parser and parameter substitution — the pure,
/// adapter-free half of the plugin system. CLI/engine behavior is covered by
/// `PluginCommandTests` in the CLI target.
final class PluginParserTests: XCTestCase {
    private let sample = """
    name: demo
    app: TextEdit
    description: A demo plugin.
    actions:
      - name: type-into
        description: Focus and type.
        params: [text]
        steps:
          - activate: true
          - wait: 80
          - assert:
              frontmost: true
          - click: 'AXTextArea'
          - type: '{{text}}'
      - name: noop
        steps:
          - wait: 10
    """

    func testParsesHeaderAndActions() throws {
        let p = try PluginParser.parse(sample, path: "/tmp/demo.yaml", defaultName: "fallback")
        XCTAssertEqual(p.name, "demo")
        XCTAssertEqual(p.app, "TextEdit")
        XCTAssertEqual(p.description, "A demo plugin.")
        XCTAssertEqual(p.path, "/tmp/demo.yaml")
        XCTAssertEqual(p.actions.map(\.name), ["type-into", "noop"])
    }

    func testActionParamsAndSteps() throws {
        let p = try PluginParser.parse(sample, defaultName: "fallback")
        let action = try XCTUnwrap(p.action(named: "type-into"))
        XCTAssertEqual(action.params, ["text"])
        XCTAssertEqual(action.description, "Focus and type.")
        XCTAssertEqual(action.steps.count, 5)
        // Second action has no params and one step.
        let noop = try XCTUnwrap(p.action(named: "noop"))
        XCTAssertEqual(noop.params, [])
        XCTAssertEqual(noop.steps.count, 1)
    }

    func testNestedMappingStepParsed() throws {
        let p = try PluginParser.parse(sample, defaultName: "fallback")
        let action = try XCTUnwrap(p.action(named: "type-into"))
        // The `assert:` step must be a mapping with `frontmost: true`.
        let assertStep = action.steps.compactMap { $0 as? [String: Any] }.first { $0["assert"] != nil }
        let mapping = try XCTUnwrap(assertStep?["assert"] as? [String: Any])
        XCTAssertEqual(mapping["frontmost"] as? Bool, true)
    }

    func testDefaultNameWhenUndeclared() throws {
        let raw = """
        app: Foo
        actions:
          - name: a
            steps:
              - wait: 1
        """
        let p = try PluginParser.parse(raw, defaultName: "from-filename")
        XCTAssertEqual(p.name, "from-filename")
    }

    func testNoActionsThrows() {
        let raw = "name: empty\napp: Foo\n"
        XCTAssertThrowsError(try PluginParser.parse(raw, defaultName: "x")) { err in
            XCTAssertEqual((err as? GuiportError)?.code, "plugin_parse")
        }
    }

    // MARK: - Substitution

    func testSubstitutesStringParam() throws {
        let out = try Substitution.apply(to: ["type": "{{text}}"], args: ["text": "hello"])
        XCTAssertEqual((out as? [String: Any])?["type"] as? String, "hello")
    }

    func testWholePlaceholderRetypedAsScalar() throws {
        // `wait: {{ms}}` with ms=80 should become the integer 80, not "80".
        let out = try Substitution.apply(to: ["wait": "{{ms}}"], args: ["ms": "80"])
        XCTAssertEqual((out as? [String: Any])?["wait"] as? Int, 80)
    }

    func testEmbeddedPlaceholderStaysString() throws {
        let out = try Substitution.apply(to: ["type": "hi {{name}}!"], args: ["name": "Edi"])
        XCTAssertEqual((out as? [String: Any])?["type"] as? String, "hi Edi!")
    }

    func testDefaultValueUsedWhenMissing() throws {
        let out = try Substitution.apply(to: "{{greeting|hello}}", args: [:])
        XCTAssertEqual(out as? String, "hello")
    }

    func testMissingParamWithoutDefaultThrows() {
        XCTAssertThrowsError(try Substitution.apply(to: "{{text}}", args: [:])) { err in
            XCTAssertEqual((err as? GuiportError)?.code, "missing_param")
        }
    }

    func testRecursesIntoNestedStructures() throws {
        let steps: [Any] = [["type": "{{a}}"], ["assert": ["front_title_contains": "{{b}}"]]]
        let out = try Substitution.apply(to: steps, args: ["a": "x", "b": "y"]) as? [Any]
        XCTAssertEqual((out?[0] as? [String: Any])?["type"] as? String, "x")
        let nested = (out?[1] as? [String: Any])?["assert"] as? [String: Any]
        XCTAssertEqual(nested?["front_title_contains"] as? String, "y")
    }
}
