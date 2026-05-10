import Foundation

public struct StepResult: Encodable {
    public let action: String
    public let passed: Bool
    public let durationMs: Int
    public let error: String?
}

public struct RunResult: Encodable {
    public let path: String
    public let passed: Bool
    public let steps: [StepResult]
    public let artifactsDir: String
}

public enum Runner {
    public static func run(path: String, artifactsDir: String) async throws -> RunResult {
        throw GuiportError(code: "not_implemented", message: "run not implemented yet")
    }
}
