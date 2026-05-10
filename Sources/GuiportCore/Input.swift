import CoreGraphics
import Foundation

public struct InputResult: Encodable {
    public let action: String
    public let ok: Bool
    public let detail: String?
}

public enum Input {
    public static func click(_ node: AXNode, app: AppTarget, button: String, count: Int, useAXPress: Bool) throws -> InputResult {
        // Stub — real implementation in input milestone.
        throw GuiportError(code: "not_implemented", message: "click not implemented yet")
    }

    public static func type(_ text: String, perCharDelayMs: Int) throws -> InputResult {
        throw GuiportError(code: "not_implemented", message: "type not implemented yet")
    }

    public static func hotkey(_ combo: String) throws -> InputResult {
        throw GuiportError(code: "not_implemented", message: "hotkey not implemented yet")
    }
}
