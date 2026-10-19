import ApplicationServices
import Foundation
import GuiportCore

struct AXElementIdentity: Hashable {
    let element: AXUIElement
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

/// Never copy a complete AXChildren array. Some virtualized apps expose an
/// enormous number of children, and a single copy can exhaust memory before a
/// node-count check gets a chance to run.
enum AXTraversal {
    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        prepare(element)
        return element
    }

    static func prepare(_ element: AXUIElement) {
        // Apple documents this as object-specific, even for an application
        // element. Prepare each descendant too; a root timeout is not inherited.
        AXUIElementSetMessagingTimeout(element, 0.5)
    }

    static func children<Result>(
        of element: AXUIElement, budget: inout TraversalBudget<AXElementIdentity>,
        visit: (AXUIElement, inout TraversalBudget<AXElementIdentity>) throws -> Result?
    ) throws -> Result? {
        try values(of: element, attribute: kAXChildrenAttribute as CFString, budget: &budget, visit: visit)
    }

    static func values<Result>(
        of element: AXUIElement, attribute: CFString, budget: inout TraversalBudget<AXElementIdentity>,
        visit: (AXUIElement, inout TraversalBudget<AXElementIdentity>) throws -> Result?
    ) throws -> Result? {
        try budget.checkTime()
        prepare(element)
        var count: CFIndex = 0
        let result = AXUIElementGetAttributeValueCount(element, attribute, &count)
        try budget.checkTime()
        if result == .attributeUnsupported || result == .noValue || result == .notImplemented { return nil }
        try requireSuccess(result, context: "count \(attribute)")
        guard count > 0 else { return nil }
        var offset = 0
        while offset < count {
            try budget.checkTime()
            let length = min(32, count - offset)
            let hit: Result? = try autoreleasepool {
                var values: CFArray?
                let error = AXUIElementCopyAttributeValues(
                    element, attribute, offset, length, &values)
                try budget.checkTime()
                try requireSuccess(error, context: "page \(attribute)")
                guard let children = values as? [AXUIElement], !children.isEmpty, children.count <= length else {
                    throw GuiportError(code: "ax_unavailable", message: "Accessibility elements changed during traversal; retry the operation.")
                }
                for child in children {
                    if let result = try autoreleasepool(invoking: { try visit(child, &budget) }) { return result }
                }
                return nil
            }
            if let hit { return hit }
            offset += length
        }
        return nil
    }

    static func requireSuccess(_ error: AXError, context: String = "attribute") throws {
        guard error != .success else { return }
        throw GuiportError(code: error == .cannotComplete ? "ax_timeout" : "ax_unavailable",
                           message: "Accessibility \(context) request failed (\(error.rawValue)); no partial result was returned.")
    }
}
