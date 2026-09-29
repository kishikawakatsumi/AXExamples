import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  var windows: [NSWindow] = []

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

    app.activate()
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    guard let winRef = attr(axApp, kAXFocusedWindowAttribute) ?? attr(axApp, kAXMainWindowAttribute) else {
      print("No focused or main window found for application '\(appName)'.")
      return
    }
    let window = winRef as! AXUIElement

    var targets: [(AXUIElement, CGRect)] = []
    var visited = 0
    func walk(_ el: AXUIElement) {
      if visited >= 4000 { return }; visited += 1
      if isEditableText(el), let f = frameAX(el), f.width > 4, f.height > 4 {
        targets.append((el, f))
      }
      for c in children(el) { walk(c) }
    }
    walk(window)

    guard !targets.isEmpty else {
      print("No editable text found in the focused or main window of application '\(appName)'.")
      return
    }
    for (el, f) in targets {
      let role = str(el, kAXRoleAttribute) ?? "?"
      let text = str(el, kAXValueAttribute) ?? ""
      let chars = (attr(el, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue ?? (text as NSString).length
      print("• \(role)  chars=\(chars)  frame=\(Int(f.width))x\(Int(f.height))")
      windows.append(ContentOverlay(cocoaRect: cocoaRect(fromAX: f), role: role, chars: chars, text: text))
    }
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

func attr(_ el: AXUIElement, _ n: String) -> CFTypeRef? {
  var v: CFTypeRef?; return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil
}
func str(_ el: AXUIElement, _ n: String) -> String? { attr(el, n) as? String }
func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func valueSettable(_ el: AXUIElement) -> Bool {
  var s = DarwinBoolean(false)
  return AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &s) == .success && s.boolValue
}

func isEditableText(_ el: AXUIElement) -> Bool {
  guard valueSettable(el) else { return false }
  if attr(el, kAXInsertionPointLineNumberAttribute) != nil { return true }
  if attr(el, kAXSelectedTextRangeAttribute) != nil { return true }
  let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField"]
  return textRoles.contains(str(el, kAXRoleAttribute) ?? "")
}
func frameAX(_ el: AXUIElement) -> CGRect? {
  guard let p = attr(el, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
        let s = attr(el, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
  var pt = CGPoint.zero, sz = CGSize.zero
  AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
  return CGRect(origin: pt, size: sz)
}
func cocoaRect(fromAX r: CGRect) -> CGRect {
  let h = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
  return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

final class ContentOverlay: NSWindow {
  init(cocoaRect: CGRect, role: String, chars: Int, text: String) {
    super.init(contentRect: cocoaRect, styleMask: .borderless, backing: .buffered, defer: false)
    isOpaque = false; backgroundColor = .clear
    level = .screenSaver
    ignoresMouseEvents = true; hasShadow = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    contentView = ContentView(role: role, chars: chars, text: text)
    setFrame(cocoaRect, display: true)
    orderFrontRegardless()
  }
}

final class ContentView: NSView {
  let role: String
  let chars: Int
  let text: String

  init(role: String, chars: Int, text: String) {
    self.role = role
    self.chars = chars
    self.text = text
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError()
  }

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let accent = NSColor.systemGreen
    accent.withAlphaComponent(0.10).setFill(); bounds.fill()
    let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; accent.setStroke(); border.stroke()

    let pad: CGFloat = 6
    let roleH: CGFloat = 17
    let bodyFont = NSFont.systemFont(ofSize: 12)
    let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
    let textAttr: [NSAttributedString.Key: Any] = [
      .font: bodyFont, .foregroundColor: NSColor.white, .paragraphStyle: para]
    let shown = text.isEmpty ? "(Empty)" : text
    let textW = bounds.width - pad * 2

    let measured = (shown as NSString).boundingRect(
      with: CGSize(width: textW, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textAttr).height
    let headerH = min(bounds.height, pad + roleH + ceil(measured) + pad)

    let header = CGRect(x: 0, y: 0, width: bounds.width, height: headerH)
    accent.setFill(); header.fill()
    let roleAttr: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white]
    (role as NSString).draw(at: CGPoint(x: pad, y: pad), withAttributes: roleAttr)
    let textRect = CGRect(x: pad, y: pad + roleH, width: textW, height: headerH - pad * 2 - roleH)
    (shown as NSString).draw(in: textRect, withAttributes: textAttr)
  }
}
