import XCTest
@testable import GuiportCore

final class SelectorTests: XCTestCase {
    func testParseRoleOnly() throws {
        let s = try Selector.parse("button")
        XCTAssertEqual(s.role, "AXButton")
        XCTAssertTrue(s.predicates.isEmpty)
        XCTAssertNil(s.index)
    }

    func testParseRoleWithName() throws {
        let s = try Selector.parse("button[name=\"Save\"]")
        XCTAssertEqual(s.role, "AXButton")
        XCTAssertEqual(s.predicates.count, 1)
        XCTAssertEqual(s.predicates[0].attr, "name")
        XCTAssertEqual(s.predicates[0].value, "Save")
    }

    func testParseContains() throws {
        let s = try Selector.parse("textfield[name~=email]")
        XCTAssertEqual(s.role, "AXTextField")
        XCTAssertEqual(s.predicates[0].op, .contains)
        XCTAssertEqual(s.predicates[0].value, "email")
    }

    func testParseIndex() throws {
        let s = try Selector.parse("AXButton[name=\"Open\"][2]")
        XCTAssertEqual(s.index, 2)
    }

    func testWildcardRole() throws {
        let s = try Selector.parse("*[name=Save]")
        XCTAssertNil(s.role)
    }

    func testMatchTree() throws {
        let leaf = AXNode(id: "/a", role: "AXButton", subrole: nil, name: "Save",
                          value: nil, identifier: "save_btn", description: nil, help: nil,
                          bounds: nil, enabled: true, focused: false, selected: false,
                          actions: ["AXPress"], children: [])
        let other = AXNode(id: "/b", role: "AXButton", subrole: nil, name: "Cancel",
                           value: nil, identifier: nil, description: nil, help: nil,
                           bounds: nil, enabled: true, focused: false, selected: false,
                           actions: ["AXPress"], children: [])
        let root = AXNode(id: "/", role: "AXWindow", subrole: nil, name: "Win",
                          value: nil, identifier: nil, description: nil, help: nil,
                          bounds: nil, enabled: true, focused: nil, selected: nil,
                          actions: [], children: [leaf, other])

        let s = try Selector.parse("button[name=\"Save\"]")
        let result = s.match(root)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.identifier, "save_btn")
    }
}
