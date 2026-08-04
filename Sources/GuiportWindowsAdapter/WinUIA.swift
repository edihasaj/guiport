#if os(Windows)
import Foundation
import WinSDK
import GuiportCore

/// UI Automation for Windows, driven through PowerShell.
///
/// Swift/WinRT COM interop is heavy, so this follows the same shape as
/// ``WinOCR``: a short PowerShell script does the COM work against
/// `System.Windows.Automation` (shipped with .NET Framework, nothing to
/// install) and hands back JSON, which is decoded into the same
/// ``AXNode`` / ``AXSummary`` the macOS adapter produces.
///
/// Producing the *same* shape matters more than it looks. Roles are mapped to
/// the AX names the selector parser normalises to, so `button[name="Save"]`
/// and `textfield` mean the same thing on both platforms and a script written
/// against a Mac keeps working on the VM. The raw UIA control type is kept in
/// `subrole`, so `[subrole=Edit]` is there when Windows really is different.
enum WinUIA {
    // MARK: - Public surface

    static func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool) throws -> AXNode {
        guard let hwnd = WinScreenshot.topLevelHwnd(forPid: DWORD(target.pid)) else {
            throw GuiportError(code: "no_window",
                               message: "no top-level window for pid \(target.pid)")
        }
        let raw = try run(hwnd: hwnd, maxDepth: maxDepth, includeHidden: includeHidden,
                          focusedOnly: false)
        guard let node = decodeNode(raw["root"]) else {
            throw GuiportError(
                code: "uia_empty",
                message: "UI Automation returned no tree for pid \(target.pid)",
                hint: "The window may still be starting, or it may render its content "
                    + "in a surface UIA cannot see (some Electron apps do). `find-text` "
                    + "reads the same screen with OCR and does not depend on the tree."
            )
        }
        return node
    }

    static func observe(target: AppTarget, app: AppInfo) throws -> AXSummary {
        guard let hwnd = WinScreenshot.topLevelHwnd(forPid: DWORD(target.pid)) else {
            throw GuiportError(code: "no_window",
                               message: "no top-level window for pid \(target.pid)")
        }
        let raw = try run(hwnd: hwnd, maxDepth: 1, includeHidden: false, focusedOnly: true)
        let root = raw["root"] as? [String: Any]
        let focused = raw["focused"] as? [String: Any]
        var rect = RECT()
        GetWindowRect(hwnd, &rect)
        let window = WindowInfo(
            title: root?["name"] as? String,
            bounds: Bounds(x: Double(rect.left), y: Double(rect.top),
                           width: Double(rect.right - rect.left),
                           height: Double(rect.bottom - rect.top))
        )
        return AXSummary(
            app: app,
            window: window,
            focusedRole: (focused?["role"] as? String).map(UIARole.ax(for:)),
            focusedName: focused?["name"] as? String,
            topLevelChildren: (root?["children"] as? [Any])?.count ?? 0
        )
    }

    /// Invoke a node through UIA rather than clicking its pixels.
    ///
    /// Worth having separately from a coordinate click: an element can be
    /// scrolled out of view, or covered, and still be perfectly invokable.
    static func invoke(node: AXNode, target: AppTarget) throws -> Bool {
        guard let id = Int(node.id) else { return false }
        guard let hwnd = WinScreenshot.topLevelHwnd(forPid: DWORD(target.pid)) else {
            return false
        }
        let raw = try run(hwnd: hwnd, maxDepth: _MAX_DEPTH, includeHidden: true,
                          focusedOnly: false, invokeIndex: id)
        return (raw["invoked"] as? Bool) ?? false
    }

    // MARK: - Plumbing

    private static let _MAX_DEPTH = 12

    private static func run(hwnd: HWND, maxDepth: Int, includeHidden: Bool,
                            focusedOnly: Bool, invokeIndex: Int? = nil) throws -> [String: Any] {
        let script = WinPowerShell.tempFile(prefix: "uia", ext: "ps1")
        try UIA_PS1.write(toFile: script, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: script) }

        var args = ["-Hwnd", String(Int(bitPattern: hwnd)),
                    "-MaxDepth", String(max(1, maxDepth))]
        if includeHidden { args.append("-IncludeHidden") }
        if focusedOnly { args.append("-FocusedOnly") }
        if let invokeIndex { args += ["-Invoke", String(invokeIndex)] }

        let out: WinPowerShell.Output
        do {
            out = try WinPowerShell.run(scriptPath: script, arguments: args)
        } catch {
            throw GuiportError(code: "uia_failed",
                               message: "could not launch PowerShell for UIA: \(error)")
        }
        if out.status != 0 {
            throw GuiportError(
                code: "uia_failed",
                message: "UI Automation failed (exit \(out.status)): "
                    + out.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                hint: "UIAutomationClient ships with .NET Framework; on Server SKUs it can "
                    + "be absent until the Desktop Experience feature is installed."
            )
        }
        guard let data = out.stdout.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GuiportError(code: "uia_failed",
                               message: "UI Automation returned unreadable output")
        }
        return obj
    }

    private static func decodeNode(_ any: Any?) -> AXNode? {
        guard let d = any as? [String: Any] else { return nil }
        let uiaRole = (d["role"] as? String) ?? "Custom"
        var bounds: Bounds?
        if let b = d["bounds"] as? [String: Any],
           let x = b["x"] as? Double, let y = b["y"] as? Double,
           let w = b["width"] as? Double, let h = b["height"] as? Double,
           w > 0, h > 0 {
            bounds = Bounds(x: x, y: y, width: w, height: h)
        }
        let children = (d["children"] as? [Any])?.compactMap(decodeNode) ?? []
        return AXNode(
            id: String(describing: d["id"] ?? ""),
            role: UIARole.ax(for: uiaRole),
            subrole: uiaRole,
            name: d["name"] as? String,
            value: d["value"] as? String,
            identifier: d["identifier"] as? String,
            description: d["description"] as? String,
            help: nil,
            bounds: bounds,
            enabled: d["enabled"] as? Bool,
            focused: d["focused"] as? Bool,
            selected: d["selected"] as? Bool,
            actions: (d["actions"] as? [Any])?.compactMap { $0 as? String } ?? [],
            children: children
        )
    }

}

/// Walks the UIA tree from a window handle and prints it as JSON.
///
/// Nodes carry a stable index (`id`) assigned in walk order, so `-Invoke <id>`
/// can find the same element again in a second pass without holding COM
/// references across processes.
private let UIA_PS1 = #"""
param(
  [Parameter(Mandatory=$true)][long]$Hwnd,
  [int]$MaxDepth = 12,
  [int]$MaxNodes = 4000,
  [switch]$IncludeHidden,
  [switch]$FocusedOnly,
  [int]$Invoke = -1
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$AE = [System.Windows.Automation.AutomationElement]
$root = $AE::FromHandle([IntPtr]$Hwnd)
if ($null -eq $root) { throw "no automation element for hwnd $Hwnd" }

$script:counter = 0
$script:invokeTarget = $null
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker

function Get-Info($el) {
  $info = @{}
  try { $info.role = $el.Current.ControlType.ProgrammaticName -replace '^ControlType\.', '' }
  catch { $info.role = "Custom" }
  foreach ($p in @(
      @{ k = 'name';       f = { $el.Current.Name } },
      @{ k = 'identifier'; f = { $el.Current.AutomationId } },
      @{ k = 'description';f = { $el.Current.HelpText } },
      @{ k = 'enabled';    f = { $el.Current.IsEnabled } },
      @{ k = 'focused';    f = { $el.Current.HasKeyboardFocus } })) {
    try { $info[$p.k] = & $p.f } catch { }
  }
  try {
    $r = $el.Current.BoundingRectangle
    if (-not [double]::IsInfinity($r.X)) {
      $info.bounds = @{ x = [double]$r.X; y = [double]$r.Y
                        width = [double]$r.Width; height = [double]$r.Height }
    }
  } catch { }
  $actions = @()
  try {
    if ($el.GetSupportedPatterns() | Where-Object { $_.ProgrammaticName -match 'Invoke' }) {
      $actions += 'AXPress'
    }
    $vp = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
      $info.value = $vp.Current.Value
      $actions += 'AXSetValue'
    }
    $sp = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sp)) {
      $info.selected = $sp.Current.IsSelected
    }
  } catch { }
  $info.actions = $actions
  return $info
}

function Walk($el, $depth) {
  if ($script:counter -ge $MaxNodes) { return $null }
  $id = $script:counter
  $script:counter++
  if ($Invoke -ge 0 -and $id -eq $Invoke) { $script:invokeTarget = $el }
  $info = Get-Info $el
  $info.id = $id
  $kids = @()
  if ($depth -lt $MaxDepth) {
    try {
      $child = $walker.GetFirstChild($el)
      while ($null -ne $child -and $script:counter -lt $MaxNodes) {
        if ($IncludeHidden -or -not $child.Current.IsOffscreen) {
          $node = Walk $child ($depth + 1)
          if ($null -ne $node) { $kids += $node }
        }
        $child = $walker.GetNextSibling($child)
      }
    } catch { }
  }
  $info.children = $kids
  return $info
}

$out = @{}
if ($FocusedOnly) {
  $info = Get-Info $root
  $info.id = 0
  $kids = @()
  try {
    $child = $walker.GetFirstChild($root)
    while ($null -ne $child) { $kids += 1; $child = $walker.GetNextSibling($child) }
  } catch { }
  $info.children = @(1..$kids.Count | ForEach-Object { @{} })
  $out.root = $info
  try {
    $f = $AE::FocusedElement
    if ($null -ne $f) { $out.focused = Get-Info $f }
  } catch { }
} else {
  $out.root = Walk $root 0
  if ($Invoke -ge 0) {
    $ok = $false
    if ($null -ne $script:invokeTarget) {
      try {
        $ip = $null
        if ($script:invokeTarget.TryGetCurrentPattern(
              [System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) {
          $ip.Invoke(); $ok = $true
        } else {
          $script:invokeTarget.SetFocus(); $ok = $true
        }
      } catch { $ok = $false }
    }
    $out.invoked = $ok
  }
}
$out | ConvertTo-Json -Depth ([Math]::Max(20, $MaxDepth + 6)) -Compress
"""#
#endif
