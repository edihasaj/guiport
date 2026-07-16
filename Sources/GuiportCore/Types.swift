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

/// Which AX root the caller wants to walk for an app. Menu-bar-only apps
/// (OneDrive, Drive, EUnifyer Desktop, etc.) expose their NSStatusItems
/// under `AXExtrasMenuBar`, not under any `AXWindow`. Without explicitly
/// asking for `.tray`, tree/find/click would return nothing useful for
/// those apps.
public enum TreeScope: String, Sendable {
    /// Window if any, else extras menu bar, else app element.
    case auto
    /// Focused or titled window (legacy default).
    case window
    /// AXExtrasMenuBar — the system status-bar items hosted by the app.
    case tray
    /// Raw application element.
    case app
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

/// Outcome of foregrounding an app via `activate` (no relaunch, no click).
public struct ActivationResult: Encodable, Sendable {
    public let action: String
    public let app: String
    public let pid: Int32
    public let bundleId: String?
    /// True if the app was already frontmost when `activate` was called.
    public let alreadyFrontmost: Bool
    /// True if the raise call was issued (i.e. it wasn't already frontmost).
    public let activated: Bool
    /// True if the app is frontmost after the call settled.
    public let frontmost: Bool

    public init(app: String, pid: Int32, bundleId: String?,
                alreadyFrontmost: Bool, activated: Bool, frontmost: Bool) {
        self.action = "activate"
        self.app = app
        self.pid = pid
        self.bundleId = bundleId
        self.alreadyFrontmost = alreadyFrontmost
        self.activated = activated
        self.frontmost = frontmost
    }
}

/// One named check inside an `assert` run.
public struct AssertCheck: Encodable, Sendable {
    public let name: String
    public let passed: Bool
    public let detail: String?

    public init(name: String, passed: Bool, detail: String?) {
        self.name = name; self.passed = passed; self.detail = detail
    }
}

/// Aggregate result of an `assert` run. `passed` is the AND of every check;
/// the command exits nonzero when it's false.
public struct AssertResult: Encodable, Sendable {
    public let action: String
    public let app: String?
    public let passed: Bool
    public let checks: [AssertCheck]

    public init(app: String?, checks: [AssertCheck]) {
        self.action = "assert"
        self.app = app
        self.checks = checks
        self.passed = checks.allSatisfy { $0.passed }
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
