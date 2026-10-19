import ApplicationServices
import Foundation
import GuiportCore

extension AXBridge {
    static func stringAttr(_ element: AXUIElement, _ attr: CFString) -> String? {
        AXTraversal.prepare(element)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
        if let s = ref as? String { return s }
        if let n = ref as? NSNumber { return n.stringValue }
        return nil
    }

    static func boolAttr(_ element: AXUIElement, _ attr: CFString) -> Bool? {
        AXTraversal.prepare(element)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
        if let n = ref as? Bool { return n }
        if let n = ref as? NSNumber { return n.boolValue }
        return nil
    }

    static func bounds(of element: AXUIElement) -> Bounds? {
        AXTraversal.prepare(element)
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() {
            AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        }
        if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() {
            AXValueGetValue(s as! AXValue, .cgSize, &size)
        }
        return Bounds(x: Double(pos.x), y: Double(pos.y), width: Double(size.width), height: Double(size.height))
    }

    static func actions(of element: AXUIElement) -> [String] {
        AXTraversal.prepare(element)
        var ref: CFArray?
        guard AXUIElementCopyActionNames(element, &ref) == .success, let arr = ref as? [String] else { return [] }
        return arr
    }
}
