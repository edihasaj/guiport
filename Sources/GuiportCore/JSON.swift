import Foundation

public enum JSONOutput {
    public static func encode<T: Encodable>(_ value: T, pretty: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func print<T: Encodable>(_ value: T, pretty: Bool = false) throws {
        let s = try encode(value, pretty: pretty)
        Swift.print(s)
    }
}

public struct GuiportError: Error, Encodable, CustomStringConvertible {
    public let code: String
    public let message: String
    public let hint: String?

    public init(code: String, message: String, hint: String? = nil) {
        self.code = code
        self.message = message
        self.hint = hint
    }

    public var description: String {
        if let hint { return "[\(code)] \(message) — \(hint)" }
        return "[\(code)] \(message)"
    }
}
