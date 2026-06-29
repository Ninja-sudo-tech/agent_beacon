import AppKit
import Core

// MARK: - Background view
// One view handles everything: move (drag non-grip area), resize (drag grip area),
// right-click menu, and draws the resize indicator.
// All in one view = no hit-test or event-routing issues with NSPanel.

private final class FloatingBackground: NSView {

    // Callbacks wired by FloatingWindowController
    var onMove:       ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onResize:     ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onRelayout:   (() -> Void)?
    var onRightClick: ((_ screenPt: NSPoint) -> Void)?

    private static let gripSize: CGFloat = 18

    private var dragMode: DragMode = .none
    private var startScreen: NSPoint = .zero

    private enum DragMode { case none, move, resize }

    // Grip indicator rect in local coordinates
    private var gripRect: NSRect {
        NSRect(x: bounds.maxX - Self.gripSize, y: bounds.minY,
               width: Self.gripSize, height: Self.gripSize)
    }

    // ── Drawing ──────────────────────────────────────────────────
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath()
        let r = gripRect
        for i in 0..<3 {
            let off = CGFloat(i) * 3.8 + 1.5
            path.move(to: NSPoint(x: r.maxX - 1.5,       y: r.minY + off))
            path.line(to: NSPoint(x: r.maxX - 1.5 - off, y: r.minY + 1.5))
        }
        NSColor.white.withAlphaComponent(0.32).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // ── Mouse events ─────────────────────────────────────────────
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        let loc = event.locationInWindow
        dragMode  = gripRect.contains(loc) ? .resize : .move
        startScreen = w.convertPoint(toScreen: loc)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let cur = w.convertPoint(toScreen: event.locationInWindow)
        let dx = cur.x - startScreen.x
        let dy = cur.y - startScreen.y
        startScreen = cur

        switch dragMode {
        case .move:   onMove?(dx, dy)
        case .resize: onResize?(dx, dy)
        case .none:   break
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let w = window else { return }
        onRightClick?(w.convertPoint(toScreen: event.locationInWindow))
    }

    // Cursor feedback
    override func resetCursorRects() {
        addCursorRect(gripRect, cursor: .crosshair)
        let moveRect = NSRect(x: bounds.minX, y: bounds.minY,
                              width: bounds.width - Self.gripSize,
                              height: bounds.height)
        addCursorRect(moveRect, cursor: .openHand)
    }
}

// MARK: - Controller

final class FloatingWindowController: NSObject {

    // ── Constants ─────────────────────────────────────────────────
    private static let pad:      CGFloat = 9
    private static let gap:      CGFloat = 8
    private static let minD:     CGFloat = 18
    private static let maxD:     CGFloat = 90
    private static let defaultD: CGFloat = 36

    private static func defaultSize() -> NSSize {
        let d = defaultD
        return NSSize(width: pad + d + pad,
                      height: d * 3 + gap * 2 + pad * 2)
    }

    // ── State ──────────────────────────────────────────────────────
    private(set) var panel: NSPanel?
    private var bgView: FloatingBackground?
    private var circles:  [NSView]       = []
    private var labels:   [NSTextField]  = []

    /// Set by AppDelegate; called when user right-clicks the window.
    var onShowMenu: ((NSPoint) -> Void)?

    private let defaults = UserDefaults.standard
    private let kX = "ab.float.x", kY = "ab.float.y"
    private let kW = "ab.float.w", kH = "ab.float.h"

    var isVisible: Bool { panel?.isVisible ?? false }

    // ── Public API ─────────────────────────────────────────────────

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
        let order = ["claude", "codex", "antigravity"]
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for (i, agent) in order.enumerated() {
                guard i < self.circles.count else { break }
                let state = statuses.first(where: { $0.agent == agent })?.state ?? .idle
                self.circles[i].layer?.backgroundColor = self.circleColor(state).cgColor
                self.circles[i].layer?.shadowOpacity   = state == .idle ? 0 : 0.5
            }
        }
    }

    // ── Build ──────────────────────────────────────────────────────

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
        // No isMovableByWindowBackground — we handle movement manually.

        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove(_:)),
            name: NSWindow.didMoveNotification, object: p)

        // Background
        let bg = FloatingBackground(frame: p.contentView!.bounds)
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.60).cgColor
        bg.layer?.masksToBounds   = true
        p.contentView?.addSubview(bg)
        bgView = bg

        // Wire callbacks
        bg.onMove = { [weak self] dx, dy in
            guard let w = self?.panel else { return }
            w.setFrameOrigin(NSPoint(x: w.frame.origin.x + dx,
                                     y: w.frame.origin.y + dy))
            self?.persist()
        }
        bg.onResize = { [weak self] dx, dy in
            self?.handleResize(dx: dx, dy: dy)
        }
        bg.onRightClick = { [weak self] pt in
            self?.onShowMenu?(pt)
        }

        // Circles + labels
        let letters = ["C", "X", "A"]
        circles = []
        labels  = []
        let showL = Preferences.shared.showFloatingLabels

        for i in 0..<3 {
            let circle = NSView()
            circle.wantsLayer = true
            circle.layer?.masksToBounds   = true
            circle.layer?.backgroundColor = circleColor(.idle).cgColor
            circle.layer?.shadowColor     = NSColor.white.cgColor
            circle.layer?.shadowRadius    = 6
            circle.layer?.shadowOpacity   = 0
            circle.layer?.shadowOffset    = .zero
            bg.addSubview(circle)
            circles.append(circle)

            let lbl = NSTextField(labelWithString: letters[i])
            lbl.alignment       = .center
            lbl.isBezeled       = false
            lbl.isEditable      = false
            lbl.drawsBackground = false
            lbl.isHidden        = !showL
            circle.addSubview(lbl)
            labels.append(lbl)
        }

        panel = p
        relayout()
    }

    // ── Layout ─────────────────────────────────────────────────────

    private func relayout() {
        guard let p = panel, let bg = bgView else { return }
        let w = p.frame.width
        let h = p.frame.height

        let d   = diameter(for: h)
        let gap = Self.gap
        let pad = Self.pad

        // Pill background
        bg.frame = NSRect(x: 0, y: 0, width: w, height: h)
        bg.layer?.cornerRadius = min(w, h) / 2.2
        bg.needsDisplay = true   // redraw grip indicator

        let totalH = d * 3 + gap * 2
        let startY = (h - totalH) / 2
        let startX = (w - d) / 2

        let fontSize = max(8, d * 0.42)
        let font     = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let showL    = Preferences.shared.showFloatingLabels

        for i in 0..<3 {
            guard i < circles.count, i < labels.count else { break }
            // i=0 → Claude (top) = highest y
            let cy = startY + CGFloat(2 - i) * (d + gap)

            circles[i].frame = NSRect(x: startX, y: cy, width: d, height: d)
            circles[i].layer?.cornerRadius = d / 2

            // Precise vertical centering using actual font metrics
            let hide = !showL || d < 22
            labels[i].isHidden = hide
            if !hide {
                let letter = labels[i].stringValue
                let measured = (letter as NSString).size(withAttributes: [.font: font])
                // Center the measured rect inside the circle
                let lx = (d - measured.width)  / 2
                let ly = (d - measured.height) / 2
                labels[i].frame = NSRect(x: lx, y: ly,
                                          width: measured.width  + 1,
                                          height: measured.height + 1)
                labels[i].font      = font
                labels[i].textColor = .black
            }
        }
    }

    // ── Resize ─────────────────────────────────────────────────────

    private func handleResize(dx: CGFloat, dy: CGFloat) {
        guard let p = panel else { return }
        let minH = Self.minD * 3 + Self.gap * 2 + Self.pad * 2
        let minW = Self.pad + Self.minD + Self.pad

        let f    = p.frame
        let newW = max(minW, f.width  + dx)
        let newH = max(minH, f.height - dy)   // drag ↓ → dy<0 → height grows
        let newY = f.origin.y + (f.height - newH)

        p.setFrame(NSRect(x: f.origin.x, y: newY, width: newW, height: newH),
                   display: true)
        relayout()
        persist()
    }

    // ── Persistence ────────────────────────────────────────────────

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

    // ── Helpers ────────────────────────────────────────────────────

    private func diameter(for windowHeight: CGFloat) -> CGFloat {
        let avail = windowHeight - Self.pad * 2 - Self.gap * 2
        return max(Self.minD, min(Self.maxD, avail / 3))
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
