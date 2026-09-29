import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  var windows: [NSWindow] = []

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    let appName = "Safari"

    let maxItems = 2000
    let minChars = 1

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

    var targets: [(String, CGRect, String)] = []
    var visited = 0
    func walk(_ el: AXUIElement) {
      if visited >= 8000 || targets.count >= maxItems { return }
      visited += 1
      let role = str(el, kAXRoleAttribute) ?? "?"
      if textRoles.contains(role), let t = textOf(el), t.count >= minChars,
         let f = frameAX(el), f.width > 4, f.height > 4 {
        targets.append((role, f, t))
      }
      for c in children(el) {
        walk(c)
      }
    }
    walk(window)
    guard !targets.isEmpty else {
      print("No text elements found in the window.")
      return
    }
    targets.sort { a, b in abs(a.1.minY - b.1.minY) > 6 ? a.1.minY < b.1.minY : a.1.minX < b.1.minX }

    let screen = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)!.frame
    let pad: CGFloat = 6
    let bodyFont = NSFont.systemFont(ofSize: 12)
    let paraM = NSMutableParagraphStyle()
    paraM.lineBreakMode = .byWordWrapping
    let measAttr: [NSAttributedString.Key: Any] = [.font: bodyFont, .paragraphStyle: paraM]

    for (i, t) in targets.enumerated() {
      let (role, f, text) = t
      let box = cocoaRect(fromAX: f)

      let fw = min(max(box.width, 220), screen.width - 16)
      let fx = min(max(box.minX, screen.minX + 8), screen.maxX - fw - 8)
      let measured = (text as NSString).boundingRect(
        with: CGSize(width: fw - pad * 2, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: measAttr).height
      let fh = min(max(24, 10 + ceil(measured)), 200)


      var fyBottom = box.minY - fh
      if fyBottom < screen.minY + 8 { fyBottom = box.maxY }
      let footer = CGRect(x: fx, y: fyBottom, width: fw, height: fh)

      let wf = box.union(footer).insetBy(dx: -2, dy: -2)
      func local(_ r: CGRect) -> CGRect { CGRect(x: r.minX - wf.minX, y: wf.maxY - r.maxY, width: r.width, height: r.height) }
      windows.append(
        CalloutOverlay(
          windowCocoa: wf,
          boxLocal: local(box),
          calloutLocal: local(footer),
          index: i + 1,
          role: role,
          text: text
        )
      )
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
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil
}
func str(_ el: AXUIElement, _ n: String) -> String? { attr(el, n) as? String }
func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func textOf(_ el: AXUIElement) -> String? {
  if let v = str(el, kAXValueAttribute), !v.isEmpty { return v }
  if let t = str(el, kAXTitleAttribute), !t.isEmpty { return t }
  if let d = str(el, kAXDescriptionAttribute), !d.isEmpty { return d }
  return nil
}
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

let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXHeading"]

final class CalloutOverlay: NSWindow {
  init(windowCocoa: CGRect, boxLocal: CGRect, calloutLocal: CGRect, index: Int, role: String, text: String) {
    super.init(contentRect: windowCocoa, styleMask: .borderless, backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    level = .screenSaver
    ignoresMouseEvents = true
    hasShadow = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    contentView = CalloutView(boxLocal: boxLocal, calloutLocal: calloutLocal, index: index, role: role, text: text)
    setFrame(windowCocoa, display: true)
    orderFrontRegardless()
  }
}

final class CalloutView: NSView {
  let boxLocal: CGRect
  let calloutLocal: CGRect
  let index: Int
  let role: String
  let text: String

  init(boxLocal: CGRect, calloutLocal: CGRect, index: Int, role: String, text: String) {
    self.boxLocal = boxLocal
    self.calloutLocal = calloutLocal
    self.index = index
    self.role = role
    self.text = text
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }
  
  override func draw(_ dirtyRect: NSRect) {
    let green = NSColor.systemGreen

    let footerBG = (NSColor.systemGreen.blended(withFraction: 0.62, of: .black) ?? NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.18, alpha: 1)).withAlphaComponent(0.95)
    let pad: CGFloat = 6

    green.withAlphaComponent(0.08).setFill()
    boxLocal.fill()
    let box = NSBezierPath(rect: boxLocal.insetBy(dx: 0.75, dy: 0.75))
    box.lineWidth = 1.5
    green.setStroke()
    box.stroke()

    let headAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white]
    let headSize = (role as NSString).size(withAttributes: headAttr)
    let headerH = min(15, boxLocal.height)
    let headerW = min(headSize.width + 8, boxLocal.width)
    let header = CGRect(x: boxLocal.minX, y: boxLocal.minY, width: headerW, height: headerH)
    green.setFill()
    header.fill()
    (role as NSString).draw(at: CGPoint(x: boxLocal.minX + 4, y: boxLocal.minY + 1), withAttributes: headAttr)

    footerBG.setFill()
    NSBezierPath(rect: calloutLocal).fill()
    let para = NSMutableParagraphStyle()
    para.lineBreakMode = .byWordWrapping
    let textAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white, .paragraphStyle: para]
    (text as NSString).draw(in: calloutLocal.insetBy(dx: pad, dy: 5), withAttributes: textAttr)
  }
}
