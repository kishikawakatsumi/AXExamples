import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  var windows: [NSWindow] = []

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    let appName = "TextEdit"
    struct Node {
      let rect: CGRect
      let role: String
      let label: String
    }

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

    var nodes: [Node] = []
    var visited = 0
    func walk(_ el: AXUIElement, depth: Int) {
      if visited >= 4000 { return }
      visited += 1
      
      let role = str(el, kAXRoleAttribute) ?? "?"
      if let f = frameAX(el), f.width > 2, f.height > 2 {
        var lbl = role
        if let sub = str(el, kAXSubroleAttribute) { lbl += "/" + sub.replacingOccurrences(of: "AX", with: "")
        }
        nodes.append(Node(rect: cocoaRect(fromAX: f), role: role, label: lbl))
      }
      for c in children(el) { walk(c, depth: depth + 1) }
    }
    walk(window, depth: 0)

    for node in nodes.sorted(by: { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }) {
      windows.append(OverlayWindow(cocoaRect: node.rect, label: node.label, color: colorFor(node.role)))
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

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}
func str(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }
func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func frameAX(_ el: AXUIElement) -> CGRect? {
  guard let p = attr(el, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
        let s = attr(el, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
  var pt = CGPoint.zero, sz = CGSize.zero
  AXValueGetValue(p as! AXValue, .cgPoint, &pt)
  AXValueGetValue(s as! AXValue, .cgSize, &sz)
  return CGRect(origin: pt, size: sz)
}

func cocoaRect(fromAX r: CGRect) -> CGRect {
  let h = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
  return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

func colorFor(_ role: String) -> NSColor {
  let hue = CGFloat(abs(role.hashValue) % 360) / 360.0
  return NSColor(hue: hue, saturation: 0.85, brightness: 0.9, alpha: 1)
}

final class OverlayWindow: NSWindow {
  init(cocoaRect: CGRect, label: String, color: NSColor) {
    super.init(contentRect: cocoaRect, styleMask: .borderless, backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    level = .screenSaver
    ignoresMouseEvents = true
    hasShadow = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    contentView = OverlayView(label: label, color: color)
    setFrame(cocoaRect, display: true)
    orderFrontRegardless()
  }
}

final class OverlayView: NSView {
  let label: String
  let color: NSColor

  init(label: String, color: NSColor) {
    self.label = label
    self.color = color
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError()
  }

  override func draw(_ dirtyRect: NSRect) {
    color.withAlphaComponent(0.08).setFill()
    bounds.fill()
    let border = NSBezierPath(rect: bounds.insetBy(dx: 0.75, dy: 0.75))
    border.lineWidth = 1.5
    color.setStroke()
    border.stroke()

    let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let size = (label as NSString).size(withAttributes: a)
    let pad: CGFloat = 3
    let boxW = min(size.width + pad * 2, bounds.width)
    let lh = size.height + pad

    let ly = max(0, bounds.height - lh)
    let bg = CGRect(x: 0, y: ly, width: boxW, height: lh)
    color.setFill()
    bg.fill()
    (label as NSString).draw(at: CGPoint(x: pad, y: ly + pad / 2), withAttributes: a)
  }
}
