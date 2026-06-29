import AppKit
import Core

// MARK: - Background view
// Handles move + resize + right-click, and draws the resize grip indicator.

private final class FloatingBackground: NSView {

    var onMove:       ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onResize:     ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onRightClick: ((_ screenPt: NSPoint) -> Void)?

    private static let gripSize: CGFloat = 18

    private enum Mode { case none, move, resize }
    private var mode: Mode = .none
    private var startScreen: NSPoint = .zero

    private var gripRect: NSRect {
        NSRect(x: bounds.maxX - Self.gripSize, y: bounds.minY,
               width: Self.gripSize, height: Self.gripSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let r = gripRect
        let path = NSBezierPath()
        for i in 0..<3 {
            let off = CGFloat(i) * 3.8 + 1.5
            path.move(to: NSPoint(x: r.maxX - 1.5,       y: r.minY + off))
            path.line(to: NSPoint(x: r.maxX - 1.5 - off, y: r.minY + 1.5))
        }
        NSColor.white.withAlphaComponent(0.30).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        let loc = event.locationInWindow
        mode = gripRect.contains(loc) ? .resize : .move
        startScreen = w.convertPoint(toScreen: loc)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let cur = w.convertPoint(toScreen: event.locationInWindow)
        let dx = cur.x - startScreen.x
        let dy = cur.y - startScreen.y
        startScreen = cur
        switch mode {
        case .move:   onMove?(dx, dy)
        case .resize: onResize?(dx, dy)
        case .none:   break
        }
    }

    override func mouseUp(with event: NSEvent) { mode = .none }

    override func rightMouseDown(with event: NSEvent) {
        guard let w = window else { return }
        onRightClick?(w.convertPoint(toScreen: event.locationInWindow))
    }

    override func resetCursorRects() {
        addCursorRect(gripRect, cursor: .crosshair)
        let rest = NSRect(x: 0, y: 0, width: bounds.width - Self.gripSize, height: bounds.height)
        addCursorRect(rest, cursor: .openHand)
    }
}

// MARK: - Controller

final class FloatingWindowController: NSObject {

    // ── Constants ────────────────────────────────────────────────────
    private static let pad:      CGFloat = 9
    private static let gap:      CGFloat = 8
    private static let labelGap: CGFloat = 10   // circle → label
    private static let labelMinW:CGFloat = 58   // min label column width
    private static let gripSz:   CGFloat = 18   // resize grip area
    private static let minD:     CGFloat = 18
    private static let maxD:     CGFloat = 90
    private static let defaultD: CGFloat = 36

    /// Minimum window width when labels hidden — circle at left + room for grip with no overlap.
    private static func narrowWidth(d: CGFloat) -> CGFloat {
        pad + d + pad + gripSz   // circle | buffer | grip
    }

    private static func defaultSize(labels: Bool) -> NSSize {
        let d = defaultD
        let h = d * 3 + gap * 2 + pad * 2
        let w = labels ? pad + d + labelGap + labelMinW + pad
                       : narrowWidth(d: d)
        return NSSize(width: w, height: h)
    }

    // ── State ────────────────────────────────────────────────────────
    private(set) var panel: NSPanel?
    private var bgView:  FloatingBackground?
    private var circles: [NSView]      = []
    private var lblViews:[NSTextField] = []

    var onShowMenu: ((NSPoint) -> Void)?

    private let defaults = UserDefaults.standard
    private let kX = "ab.float.x", kY = "ab.float.y"
    private let kW = "ab.float.w", kH = "ab.float.h"

    var isVisible: Bool { panel?.isVisible ?? false }

    // ── Public API ───────────────────────────────────────────────────

    func show() {
        if panel == nil { buildPanel() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Call after toggling showFloatingLabels; resizes window width as needed.
    func applyLabelVisibility() {
        guard let p = panel else { return }
        let showL = Preferences.shared.showFloatingLabels
        let d = diameter(for: p.frame.height)
        var f = p.frame
        if showL {
            let needed = Self.pad + d + Self.labelGap + Self.labelMinW + Self.pad
            if f.width < needed {
                f.size.width = needed
                p.setFrame(f, display: true)
            }
        } else {
            // Keep grip zone clear of circles: pad + d + pad + gripSz
            f.size.width = Self.narrowWidth(d: d)
            p.setFrame(f, display: true)
        }
        relayout()
        persist()
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
                self.circles[i].layer?.shadowOpacity   = state == .idle ? 0 : 0.50
            }
        }
    }

    // ── Build ────────────────────────────────────────────────────────

    private func buildPanel() {
        let showL  = Preferences.shared.showFloatingLabels
        let sz     = savedSize() ?? Self.defaultSize(labels: showL)
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

        bg.onMove = { [weak self] dx, dy in
            guard let w = self?.panel else { return }
            w.setFrameOrigin(NSPoint(x: w.frame.origin.x + dx,
                                     y: w.frame.origin.y + dy))
            self?.persist()
        }
        bg.onResize = { [weak self] dx, dy in self?.handleResize(dx: dx, dy: dy) }
        bg.onRightClick = { [weak self] pt in self?.onShowMenu?(pt) }

        // Circles (subviews of bg)
        circles  = []
        lblViews = []
        let names = ["Claude", "Codex", "Antigr"]

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

            // Label to the right of the circle (sibling, not child)
            let lbl = NSTextField(labelWithString: names[i])
            lbl.alignment       = .left
            lbl.isBezeled       = false
            lbl.isEditable      = false
            lbl.drawsBackground = false
            lbl.textColor       = NSColor(white: 0.92, alpha: 1)
            lbl.lineBreakMode   = .byTruncatingTail
            lbl.isHidden        = !showL
            bg.addSubview(lbl)
            lblViews.append(lbl)
        }

        panel = p
        relayout()
    }

    // ── Layout ───────────────────────────────────────────────────────

    private func relayout() {
        guard let p = panel, let bg = bgView else { return }
        let w = p.frame.width
        let h = p.frame.height

        let d    = diameter(for: h)
        let gap  = Self.gap
        let pad  = Self.pad
        let lgap = Self.labelGap
        let showL = Preferences.shared.showFloatingLabels

        // Background pill — adapts corner radius
        bg.frame = NSRect(x: 0, y: 0, width: w, height: h)
        bg.layer?.cornerRadius = showL ? 12 : min(w, h) / 2.2
        bg.needsDisplay = true

        // Font scales with circle size
        let fontSize = max(9, d * 0.38)
        let font     = NSFont.systemFont(ofSize: fontSize, weight: .semibold)

        let totalH = d * 3 + gap * 2
        let startY = (h - totalH) / 2
        // Circles always at left pad — grip is reserved at the far right
        let circleX: CGFloat = pad

        let labelX = pad + d + lgap
        let labelW = max(0, w - labelX - pad)

        for i in 0..<3 {
            guard i < circles.count, i < lblViews.count else { break }
            let cy = startY + CGFloat(2 - i) * (d + gap)

            // Circle
            circles[i].frame = NSRect(x: circleX, y: cy, width: d, height: d)
            circles[i].layer?.cornerRadius = d / 2

            // Label — vertically centered with circle using measured text height
            let textH = (lblViews[i].stringValue as NSString)
                .size(withAttributes: [.font: font]).height
            let labelY = cy + (d - textH) / 2

            lblViews[i].frame    = NSRect(x: labelX, y: labelY, width: labelW, height: textH + 2)
            lblViews[i].font     = font
            lblViews[i].isHidden = !showL || labelW < 10
        }
    }

    // ── Resize ───────────────────────────────────────────────────────

    private func handleResize(dx: CGFloat, dy: CGFloat) {
        guard let p = panel else { return }
        let showL = Preferences.shared.showFloatingLabels
        let minH  = Self.minD * 3 + Self.gap * 2 + Self.pad * 2
        let minW  = showL
            ? Self.pad + Self.minD + Self.labelGap + 30 + Self.pad
            : Self.narrowWidth(d: Self.minD)

        let f    = p.frame
        let newW = max(minW, f.width  + dx)
        let newH = max(minH, f.height - dy)
        let newY = f.origin.y + (f.height - newH)

        p.setFrame(NSRect(x: f.origin.x, y: newY, width: newW, height: newH), display: true)
        relayout()
        persist()
    }

    // ── Persistence ──────────────────────────────────────────────────

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

    // ── Helpers ──────────────────────────────────────────────────────

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
