import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    let appName = "TextEdit"

    let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
    let options = [trustedCheckOptionPrompt: true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
      waitPermisionGranted()
    }

    guard let app = NSWorkspace.shared.runningApplications.first(where: {
      $0.localizedName == appName || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(appName) ?? false)
    }) else {
      print("Application '\(appName)' is not running.")
      return
    }

    func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
      var v: CFTypeRef?
      return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    func str(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }
    func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

    let axApp = AXUIElementCreateApplication(app.processIdentifier)

    guard let winRef = attr(axApp, kAXFocusedWindowAttribute) ?? attr(axApp, kAXMainWindowAttribute) else {
      return
    }
    let window = winRef as! AXUIElement

    func short(_ s: String, _ n: Int = 40) -> String {
      let f = s.replacingOccurrences(of: "\n", with: "⏎")
      return f.count <= n ? f : String(f.prefix(n)) + "…"
    }
    func describe(_ el: AXUIElement) -> String {
      var p = [str(el, kAXRoleAttribute) ?? "?"]
      if let sub = str(el, kAXSubroleAttribute) { p.append(sub) }
      if let t = str(el, kAXTitleAttribute), !t.isEmpty { p.append("title=\"\(short(t))\"") }
      if let v = str(el, kAXValueAttribute), !v.isEmpty { p.append("value=\"\(short(v))\"") }
      if let d = str(el, kAXDescriptionAttribute), !d.isEmpty { p.append("desc=\"\(short(d))\"") }
      if let n = (attr(el, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue { p.append("chars=\(n)") }
      return p.joined(separator: "  ")
    }

    var visited = 0
    let maxNodes = 5000
    func dump(_ el: AXUIElement, _ depth: Int) {
      if visited >= maxNodes { return }
      visited += 1
      print(String(repeating: "  ", count: depth) + "• " + describe(el))
      for c in children(el) { dump(c, depth + 1) }
    }

    dump(window, 0)
  }

  private func waitPermisionGranted() {
    Task {
      try? await Task.sleep(nanoseconds: 3_000_000)
      if !AXIsProcessTrusted() {
        waitPermisionGranted()
      }
    }
  }
}
