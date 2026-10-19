import Foundation

/// A single budget follows an entire AX operation, including hidden nodes and
/// retries at alternative roots. Depth alone does not bound a wide or cyclic graph.
public struct TraversalBudget<Identity: Hashable> {
    public static var defaultNodeLimit: Int { 5_000 }
    public static var defaultTextLimit: Int { 1_048_576 }
    private let nodeLimit: Int
    private let textLimit: Int
    private let deadline: TimeInterval
    private let now: () -> TimeInterval
    private var ancestors: Set<Identity> = []
    private var nodes = 0
    private var textBytes = 0

    public init(nodeLimit: Int = 5_000, textLimit: Int = 1_048_576,
                seconds: TimeInterval = 10,
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.nodeLimit = nodeLimit
        self.textLimit = textLimit
        self.now = now
        self.deadline = now() + seconds
    }

    public mutating func enter(_ identity: Identity) throws {
        try checkTime()
        guard nodes < nodeLimit else {
            throw GuiportError(code: "ax_node_limit", message: "Accessibility traversal exceeded \(nodeLimit) nodes.",
                               hint: "Use a focused window, a narrower selector, or OCR.")
        }
        guard ancestors.insert(identity).inserted else {
            throw GuiportError(code: "ax_cycle", message: "Accessibility children contain a cycle.",
                               hint: "Use OCR or inspect a different window.")
        }
        nodes += 1
    }

    public mutating func leave(_ identity: Identity) {
        ancestors.remove(identity)
    }

    public mutating func chargeText(_ text: String?) throws {
        guard let text else { return }
        let bytes = text.utf8.count
        guard bytes <= textLimit - textBytes else {
            throw GuiportError(code: "ax_text_limit", message: "Accessibility text exceeded \(textLimit) bytes.",
                               hint: "Use a narrower selector or OCR.")
        }
        textBytes += bytes
        try checkTime()
    }

    public func checkTime() throws {
        guard now() < deadline else {
            throw GuiportError(code: "ax_timeout", message: "Accessibility traversal exceeded its time budget.",
                               hint: "The app may be unresponsive. Use OCR or retry after it responds.")
        }
    }

    public static func validateDepth(_ depth: Int) throws {
        guard (0...60).contains(depth) else {
            throw GuiportError(code: "ax_depth_limit", message: "Tree depth must be between 0 and 60.")
        }
    }
}
