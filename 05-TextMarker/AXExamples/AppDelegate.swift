import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow?

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    let appName = "Safari"

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

    var webs: [AXUIElement] = []
    var budget = 20000
    collectWebAreas(winRef as! AXUIElement, &webs, &budget)
    let pairs = webs.compactMap { w -> (AXUIElement, String)? in fullText(of: w).map { (w, $0) } }
    guard let (bodyWeb, text) = pairs.max(by: { $0.1.count < $1.1.count }), !text.isEmpty else {
      print("No WebArea/TextMarker content found for application '\(appName)'.")
      return
    }
    guard let f = frameAX(bodyWeb) else {
      print("No frame found for WebArea in application '\(appName)'.")
      return
    }

    var leafBudget = 20000
    let leafN = countStaticText(bodyWeb, &leafBudget)
    let role = attr(bodyWeb, kAXRoleAttribute) as? String ?? "AXWebArea"

    let rectAX = fullRange(of: bodyWeb).flatMap { boundsAX(bodyWeb, $0) } ?? f
    let header = "\(role)"
    window = TMOverlay(cocoaRect: cocoaRect(fromAX: rectAX), header: header, text: text)
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
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil
}
func param(_ el: AXUIElement, _ n: String, _ p: CFTypeRef) -> CFTypeRef? {
  var v: CFTypeRef?
  return AXUIElementCopyParameterizedAttributeValue(el, n as CFString, p, &v) == .success ? v : nil
}
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
func collectWebAreas(_ el: AXUIElement, _ out: inout [AXUIElement], _ budget: inout Int) {
  if budget <= 0 { return }
  budget -= 1
  if attr(el, "AXStartTextMarker") != nil { out.append(el) }
  for c in children(el) { collectWebAreas(c, &out, &budget) }
}
func fullRange(of web: AXUIElement) -> CFTypeRef? {
  guard let start = attr(web, "AXStartTextMarker"),
        let end   = attr(web, "AXEndTextMarker") else { return nil }
  return param(web, "AXTextMarkerRangeForUnorderedTextMarkers", [start, end] as CFArray)
}
func fullText(of web: AXUIElement) -> String? {
  fullRange(of: web).flatMap { param(web, "AXStringForTextMarkerRange", $0) as? String }
}
func boundsAX(_ web: AXUIElement, _ range: CFTypeRef) -> CGRect? {
  guard let v = param(web, "AXBoundsForTextMarkerRange", range), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
  var r = CGRect.zero
  return AXValueGetValue(v as! AXValue, .cgRect, &r) ? r : nil
}
func countStaticText(_ el: AXUIElement, _ budget: inout Int) -> Int {
  if budget <= 0 { return 0 }
  budget -= 1
  var n = ((attr(el, kAXRoleAttribute) as? String) == "AXStaticText") ? 1 : 0
  for c in children(el) { n += countStaticText(c, &budget) }
  return n
}

final class TMOverlay: NSWindow {
  init(cocoaRect: CGRect, header: String, text: String) {
    super.init(contentRect: cocoaRect, styleMask: .borderless, backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    level = .screenSaver
    ignoresMouseEvents = true
    hasShadow = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    contentView = TMView(header: header, text: text)
    setFrame(cocoaRect, display: true)
    orderFrontRegardless()
  }
}

final class TMView: NSView {
  let header: String
  let text: String

  init(header: String, text: String) {
    self.header = header
    self.text = text
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }
  
  override func draw(_ dirtyRect: NSRect) {
    let green = NSColor.systemGreen
    let bodyBG = (NSColor.systemGreen.blended(withFraction: 0.62, of: .black) ?? .black).withAlphaComponent(0.93)

    bodyBG.setFill()
    bounds.fill()
    let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
    border.lineWidth = 2
    green.setStroke()
    border.stroke()

    let pad: CGFloat = 8
    let hAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white]
    let hH: CGFloat = 20
    green.setFill()
    CGRect(x: 0, y: 0, width: bounds.width, height: hH).fill()
    (header as NSString).draw(at: CGPoint(x: pad, y: 3), withAttributes: hAttr)

    let para = NSMutableParagraphStyle()
    para.lineBreakMode = .byWordWrapping
    let tAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white, .paragraphStyle: para]
    let tRect = CGRect(x: pad, y: hH + 6, width: bounds.width - pad * 2, height: bounds.height - hH - pad - 6)
    (text as NSString).draw(in: tRect, withAttributes: tAttr)
  }
}
