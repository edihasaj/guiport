import Foundation

// MARK: - Geometry

public struct Bounds: Encodable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

// MARK: - Apps

public struct AppInfo: Encodable, Sendable {
    public let name: String
    public let bundleId: String?
    public let pid: Int32?
    public let active: Bool
    public let windowCount: Int

    public init(name: String, bundleId: String?, pid: Int32?, active: Bool, windowCount: Int) {
        self.name = name
        self.bundleId = bundleId
        self.pid = pid
        self.active = active
        self.windowCount = windowCount
    }
}

public struct AppTarget: Sendable {
    public let name: String
    public let bundleId: String?
    public let pid: Int32
    public let windowTitleHint: String?

    public init(name: String, bundleId: String?, pid: Int32, windowTitleHint: String? = nil) {
        self.name = name
        self.bundleId = bundleId
        self.pid = pid
        self.windowTitleHint = windowTitleHint
    }
}

// MARK: - AX

public struct WindowInfo: Encodable, Sendable {
    public let title: String?
    public let bounds: Bounds?

    public init(title: String?, bounds: Bounds?) {
        self.title = title; self.bounds = bounds
    }
}

public struct AXSummary: Encodable, Sendable {
    public let app: AppInfo
    public let window: WindowInfo?
    public let focusedRole: String?
    public let focusedName: String?
    public let topLevelChildren: Int

    public init(app: AppInfo, window: WindowInfo?, focusedRole: String?, focusedName: String?, topLevelChildren: Int) {
        self.app = app
        self.window = window
        self.focusedRole = focusedRole
        self.focusedName = focusedName
        self.topLevelChildren = topLevelChildren
    }
}

public struct AXNode: Encodable, Sendable {
    public let id: String
    public let role: String
    public let subrole: String?
    public let name: String?
    public let value: String?
    public let identifier: String?
    public let description: String?
    public let help: String?
    public let bounds: Bounds?
    public let enabled: Bool?
    public let focused: Bool?
    public let selected: Bool?
    public let actions: [String]
    public var children: [AXNode]

    public init(id: String, role: String, subrole: String?, name: String?, value: String?,
                identifier: String?, description: String?, help: String?, bounds: Bounds?,
                enabled: Bool?, focused: Bool?, selected: Bool?, actions: [String], children: [AXNode]) {
        self.id = id; self.role = role; self.subrole = subrole; self.name = name; self.value = value
        self.identifier = identifier; self.description = description; self.help = help
        self.bounds = bounds; self.enabled = enabled; self.focused = focused; self.selected = selected
        self.actions = actions; self.children = children
    }
}

// MARK: - Action results

public struct InputResult: Encodable, Sendable {
    public let action: String
    public let ok: Bool
    public let detail: String?
    public let target: String?

    public init(action: String, ok: Bool, detail: String?, target: String?) {
        self.action = action; self.ok = ok; self.detail = detail; self.target = target
    }
}

public struct ScreenshotResult: Encodable, Sendable {
    public let path: String
    public let width: Int
    public let height: Int
    public let scope: String

    public init(path: String, width: Int, height: Int, scope: String) {
        self.path = path; self.width = width; self.height = height; self.scope = scope
    }
}

public struct OCRMatch: Encodable, Sendable {
    public let text: String
    public let confidence: Double
    public let bounds: Bounds
    public let centerX: Double
    public let centerY: Double

    public init(text: String, confidence: Double, bounds: Bounds, centerX: Double, centerY: Double) {
        self.text = text; self.confidence = confidence; self.bounds = bounds
        self.centerX = centerX; self.centerY = centerY
    }
}
