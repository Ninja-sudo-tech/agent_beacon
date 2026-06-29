import AppKit
import Core

// MARK: - Draggable background view
// Handles window-move (drag anywhere except resize grip) and right-click menu.
// Cannot use isMovableByWindowBackground because it eats drag events before
// subviews (like the resize handle) can receive them.
private final class FloatingBackground: NSView {
    var onRightClick: ((NSPoint) -> Void)?   // screen-space point for menu pop-up
    weak var resizeGrip: NSView?

    private var dragStart: NSPoint = .zero   // in screen coordinates

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        dragStart = w.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let cur = w.convertPoint(toScreen: event.locationInWindow)
        let dx = cur.x - dragStart.x
        let dy = cur.y - dragStart.y
        dragStart = cur
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + dx,
                                  y: w.frame.origin.y + dy))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let w = window else { return }
        let screenPt = w.convertPoint(toScreen: event.locationInWindow)
        onRightClick?(screenPt)
    }

    // Let subviews (circles, grip) receive their own hit-tests normally.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point)
    }
}

// MARK: - Resize grip view
private final class ResizeHandle: NSView {
    var onDrag: ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    private var startScreen: NSPoint = .zero

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        for i in 0..<3 {
            let off = CGFloat(i) * 3.5 + 1.5
            path.move(to: NSPoint(x: bounds.maxX - 1.5,       y: bounds.minY + off))
            path.line(to: NSPoint(x: bounds.maxX - 1.5 - off, y: bounds.minY + 1.5))
        }
        NSColor.white.withAlphaComponent(0.30).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        startScreen = w.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let cur = w.convertPoint(toScreen: event.locationInWindow)
        onDrag?(cur.x - startScreen.x, cur.y - startScreen.y)
        startScreen = cur
    }
}

// MARK: - Controller

final class FloatingWindowController: NSObject {

    // ── layout ────────────────────────────────────────────────────────
    private static let pad:      CGFloat = 9
    private static let gap:      CGFloat = 8
    private static let minD:     CGFloat = 20
    private static let maxD:     CGFloat = 88
    private static let defaultD: CGFloat = 36
    private static let handleSz: CGFloat = 16

    private static func defaultSize() -> NSSize {
        let d = defaultD
        return NSSize(width: pad + d + pad,
                      height: d * 3 + gap * 2 + pad * 2)
    }

    // ── state ──────────────────────────────────────────────────────────
    private(set) var panel: NSPanel?
    private var bgView: FloatingBackground?
    private var circles:  [NSView]       = []
    private var lblViews: [NSTextField]  = []
    private var grip: ResizeHandle?

    /// Set by AppDelegate — called when user right-clicks the floating window.
    var onShowMenu: ((NSPoint) -> Void)?

    private let defaults = UserDefaults.standard
    private let kX = "ab.float.x", kY = "ab.float.y"
    private let kW = "ab.float.w", kH = "ab.float.h"

    var isVisible: Bool { panel?.isVisible ?? false }

    // ── public API ────────────────────────────────────────────────────

    func show() {
        if panel == nil { buildPanel() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func applyLabelVisibility() {
        relayout()
    }

    func updateStatuses(_ statuses: [AgentStatus]) {
        guard let p = panel, p.isVisible else { return }
        let agents = ["claude", "codex", "antigravity"]
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for (i, agent) in agents.enumerated() {
                guard i < self.circles.count else { break }
                let state = statuses.first(where: { $0.agent == agent })?.state ?? .idle
                self.circles[i].layer?.backgroundColor = self.circleColor(state).cgColor
                self.circles[i].layer?.shadowOpacity   = state == .idle ? 0 : 0.55
                // Update label attributed string so shadow is reapplied at current font
                if i < self.lblViews.count, !self.lblViews[i].isHidden {
                    self.styleLabel(self.lblViews[i])
                }
            }
        }
    }

    // ── build ──────────────────────────────────────────────────────────

    private func buildPanel() {
        let sz     = savedSize() ?? Self.defaultSize()
        let origin = savedOrigin() ?? defaultOrigin(sz)

        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: sz),
            styleMask:   [.nonactivatingPanel, .borderless],
            backing:     .buffered,
            defer:       false
        )
        p.level              = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isOpaque           = false
        p.backgroundColor    = .clear
        p.hasShadow          = true
        // NOT using isMovableByWindowBackground — it intercepts drags before subviews
        // Window moving is handled manually by FloatingBackground.

        NotificationCenter.default.addObserver(self, selector: #selector(didMove(_:)),
            name: NSWindow.didMoveNotification, object: p)

        // Background
        let bg = FloatingBackground(frame: p.contentView!.bounds)
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.72).cgColor
        bg.layer?.masksToBounds   = true
        bg.onRightClick = { [weak self] screenPt in
            self?.onShowMenu?(screenPt)
        }
        p.contentView?.addSubview(bg)
        bgView = bg

        // Circles + centered labels
        let letters = ["C", "X", "A"]
        circles  = []
        lblViews = []
        for i in 0..<3 {
            let circle = NSView()
            circle.wantsLayer = true
            circle.layer?.masksToBounds   = true
            circle.layer?.backgroundColor = circleColor(.idle).cgColor
            circle.layer?.shadowColor     = NSColor.white.cgColor
            circle.layer?.shadowRadius    = 7
            circle.layer?.shadowOpacity   = 0
            circle.layer?.shadowOffset    = .zero
            bg.addSubview(circle)
            circles.append(circle)

            let lbl = NSTextField(labelWithString: letters[i])
            lbl.alignment       = .center
            lbl.isBezeled       = false
            lbl.isEditable      = false
            lbl.drawsBackground = false
            circle.addSubview(lbl)
            lblViews.append(lbl)
        }

        // Resize grip
        let g = ResizeHandle()
        g.onDrag = { [weak self] dx, dy in self?.handleResize(dx: dx, dy: dy) }
        bg.addSubview(g)
        bg.resizeGrip = g
        grip = g

        panel = p
        relayout()
    }

    // ── layout ─────────────────────────────────────────────────────────

    private func relayout() {
        guard let p = panel, let bg = bgView else { return }
        let w = p.frame.width
        let h = p.frame.height

        let d   = diameter(for: h)
        let gap = Self.gap

        // Background pill
        bg.frame = NSRect(x: 0, y: 0, width: w, height: h)
        bg.layer?.cornerRadius = min(w, h) / 2.2

        let totalH = d * 3 + gap * 2
        let startY = (h - totalH) / 2
        let startX = (w - d) / 2

        let showL    = Preferences.shared.showFloatingLabels
        let fontSize = max(8, d * 0.42)

        for i in 0..<3 {
            guard i < circles.count, i < lblViews.count else { break }
            let y = startY + CGFloat(2 - i) * (d + gap)

            circles[i].frame = NSRect(x: startX, y: y, width: d, height: d)
            circles[i].layer?.cornerRadius = d / 2

            let lh: CGFloat = fontSize + 3
            lblViews[i].frame   = NSRect(x: 0, y: (d - lh) / 2, width: d, height: lh)
            lblViews[i].isHidden = !showL || d < 22
            if !lblViews[i].isHidden {
                lblViews[i].font = .systemFont(ofSize: fontSize, weight: .bold)
                styleLabel(lblViews[i])
            }
        }

        grip?.frame = NSRect(x: w - Self.handleSz, y: 0,
                             width: Self.handleSz, height: Self.handleSz)
        grip?.needsDisplay = true
    }

    /// Apply black text + white shadow so letters are legible on any circle color.
    private func styleLabel(_ label: NSTextField) {
        let shadow = NSShadow()
        shadow.shadowColor      = NSColor.white.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 2.5
        shadow.shadowOffset     = .zero

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.black,
            .font: label.font ?? NSFont.boldSystemFont(ofSize: 13),
            .shadow: shadow
        ]
        label.attributedStringValue = NSAttributedString(
            string: label.stringValue, attributes: attrs
        )
    }

    // ── resize ──────────────────────────────────────────────────────────

    private func handleResize(dx: CGFloat, dy: CGFloat) {
        guard let p = panel else { return }
        let minH = Self.minD * 3 + Self.gap * 2 + Self.pad * 2
        let minW = Self.pad + Self.minD + Self.pad

        let f    = p.frame
        let newW = max(minW, f.width  + dx)
        let newH = max(minH, f.height - dy)
        let newY = f.origin.y + (f.height - newH)

        p.setFrame(NSRect(x: f.origin.x, y: newY, width: newW, height: newH),
                   display: true)
        relayout()
        persist()
    }

    // ── persistence ─────────────────────────────────────────────────────

    private func persist() {
        guard let p = panel else { return }
        defaults.set(Double(p.frame.origin.x), forKey: kX)
        defaults.set(Double(p.frame.origin.y), forKey: kY)
        defaults.set(Double(p.frame.width),    forKey: kW)
        defaults.set(Double(p.frame.height),   forKey: kH)
    }

    @objc private func didMove(_ n: Notification) { persist() }

    private func savedSize() -> NSSize? {
        let w = defaults.double(forKey: kW)
        let h = defaults.double(forKey: kH)
        guard w > 10, h > 10 else { return nil }
        return NSSize(width: w, height: h)
    }

    private func savedOrigin() -> NSPoint? {
        let x = defaults.double(forKey: kX)
        let y = defaults.double(forKey: kY)
        guard x != 0 || y != 0 else { return nil }
        let pt = NSPoint(x: x, y: y)
        if let screen = NSScreen.main, screen.frame.contains(pt) { return pt }
        return nil
    }

    private func defaultOrigin(_ size: NSSize) -> NSPoint {
        let sf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: sf.maxX - size.width - 28, y: sf.maxY - size.height - 28)
    }

    // ── helpers ─────────────────────────────────────────────────────────

    private func diameter(for windowHeight: CGFloat) -> CGFloat {
        let available = windowHeight - Self.pad * 2 - Self.gap * 2
        return max(Self.minD, min(Self.maxD, available / 3))
    }

    private func circleColor(_ state: AgentState) -> NSColor {
        switch state {
        case .idle:    return NSColor(white: 0.18, alpha: 1)
        case .running: return NSColor(red: 0.96, green: 0.76, blue: 0.00, alpha: 1)
        case .waiting: return NSColor(red: 0.92, green: 0.18, blue: 0.18, alpha: 1)
        case .done:    return NSColor(red: 0.16, green: 0.80, blue: 0.36, alpha: 1)
        case .error:   return NSColor(red: 0.62, green: 0.18, blue: 0.90, alpha: 1)
        }
    }
}
