import AppKit
import Core

// MARK: - Resize grip view

private final class ResizeHandle: NSView {
    var onDrag: ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    private var startScreen: NSPoint = .zero

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Three subtle diagonal lines in the bottom-right corner
        let path = NSBezierPath()
        for i in 0..<3 {
            let off = CGFloat(i) * 3.5 + 1.5
            path.move(to: NSPoint(x: bounds.maxX - 1.5,         y: bounds.minY + off))
            path.line(to: NSPoint(x: bounds.maxX - 1.5 - off,   y: bounds.minY + 1.5))
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
        let dx = cur.x - startScreen.x
        let dy = cur.y - startScreen.y
        startScreen = cur
        onDrag?(dx, dy)
    }
}

// MARK: - Floating window controller

final class FloatingWindowController: NSObject {

    // ── layout constants ────────────────────────────────────────────
    private static let pad:      CGFloat = 8
    private static let circleGap:CGFloat = 8
    private static let labelGap: CGFloat = 8
    private static let minD:     CGFloat = 18    // min circle diameter
    private static let maxD:     CGFloat = 80    // max circle diameter
    private static let defaultD: CGFloat = 34
    private static let labelW:   CGFloat = 68    // default label column width
    private static let handleSz: CGFloat = 16

    private static func defaultSize(labels: Bool) -> NSSize {
        let d = defaultD
        let h = d * 3 + circleGap * 2 + pad * 2
        let w = labels
            ? pad + d + labelGap + labelW + pad
            : pad + d + pad
        return NSSize(width: w, height: h)
    }

    // ── state ───────────────────────────────────────────────────────
    private(set) var panel: NSPanel?
    private var bg: NSView?
    private var circles: [NSView] = []
    private var lblViews: [NSTextField] = []
    private var grip: ResizeHandle?
    private var lastStatuses: [AgentStatus] = []

    private let defaults = UserDefaults.standard
    private let kX = "ab.float.x", kY = "ab.float.y"
    private let kW = "ab.float.w", kH = "ab.float.h"

    var isVisible: Bool { panel?.isVisible ?? false }

    // ── public API ─────────────────────────────────────────────────

    func show() {
        if panel == nil { buildPanel() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Call after toggling showLabels preference to relayout.
    func applyLabelVisibility() {
        guard let p = panel else { return }
        let showL = Preferences.shared.showFloatingLabels
        let d = diameter(for: p.frame.height)
        var f = p.frame
        if showL {
            let needed = Self.pad + d + Self.labelGap + Self.labelW + Self.pad
            if f.width < needed { f.size.width = needed; p.setFrame(f, display: true) }
        } else {
            let narrow = Self.pad + d + Self.pad
            f.size.width = narrow
            p.setFrame(f, display: true)
        }
        relayout()
        persist()
    }

    func updateStatuses(_ statuses: [AgentStatus]) {
        lastStatuses = statuses
        guard let p = panel, p.isVisible else { return }
        let agents = ["claude", "codex", "antigravity"]
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for (i, agent) in agents.enumerated() {
                guard i < self.circles.count else { break }
                let state = statuses.first(where: { $0.agent == agent })?.state ?? .idle
                let col = self.stateColor(state)
                self.circles[i].layer?.backgroundColor = col.cgColor
                self.circles[i].layer?.shadowOpacity   = state == .idle ? 0 : 0.65
                if i < self.lblViews.count {
                    self.lblViews[i].textColor = state == .idle
                        ? NSColor(white: 0.55, alpha: 1)
                        : col.blended(withFraction: 0.35, of: .white) ?? .white
                }
            }
        }
    }

    // ── build ──────────────────────────────────────────────────────

    private func buildPanel() {
        let showL = Preferences.shared.showFloatingLabels
        let sz    = savedSize() ?? Self.defaultSize(labels: showL)
        let origin = savedOrigin() ?? defaultOrigin(size: sz)

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
        p.isMovableByWindowBackground = true

        NotificationCenter.default.addObserver(self, selector: #selector(windowMoved(_:)),
            name: NSWindow.didMoveNotification, object: p)

        // background pill
        let background = NSView(frame: p.contentView!.bounds)
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.52).cgColor
        background.layer?.masksToBounds   = true
        p.contentView?.addSubview(background)
        bg = background

        // circles + labels
        let agentNames = ["C", "X", "A"]
        circles = []
        lblViews = []
        for i in 0..<3 {
            let circle = NSView()
            circle.wantsLayer = true
            circle.layer?.masksToBounds   = true
            circle.layer?.backgroundColor = stateColor(.idle).cgColor
            circle.layer?.shadowColor     = NSColor.white.cgColor
            circle.layer?.shadowRadius    = 5
            circle.layer?.shadowOpacity   = 0
            circle.layer?.shadowOffset    = .zero
            background.addSubview(circle)
            circles.append(circle)

            let lbl = NSTextField(labelWithString: agentNames[i])
            lbl.font          = .systemFont(ofSize: 11, weight: .medium)
            lbl.textColor     = NSColor(white: 0.55, alpha: 1)
            lbl.isBezeled     = false
            lbl.isEditable    = false
            lbl.drawsBackground = false
            lbl.lineBreakMode = .byTruncatingTail
            background.addSubview(lbl)
            lblViews.append(lbl)
        }

        // resize grip
        let g = ResizeHandle()
        g.onDrag = { [weak self] dx, dy in self?.handleResize(dx: dx, dy: dy) }
        background.addSubview(g)
        grip = g

        panel = p
        relayout()
    }

    /// Recomputes all subview frames from the current panel size.
    private func relayout() {
        guard let p = panel, let background = bg else { return }
        let w = p.frame.width
        let h = p.frame.height
        let showL = Preferences.shared.showFloatingLabels

        let d    = diameter(for: h)
        let pad  = Self.pad
        let gap  = Self.circleGap
        let lgap = Self.labelGap
        let hsz  = Self.handleSz

        // corner radius — pill when narrow, rounded rect when wide
        background.frame = NSRect(x: 0, y: 0, width: w, height: h)
        background.layer?.cornerRadius = min(w / 2, d / 2 + pad)

        let totalCircleH = d * 3 + gap * 2
        let startY = (h - totalCircleH) / 2

        for i in 0..<3 {
            guard i < circles.count, i < lblViews.count else { break }
            // i=0 → Claude at top → highest y → reverse index
            let y = startY + CGFloat(2 - i) * (d + gap)

            circles[i].frame = NSRect(x: pad, y: y, width: d, height: d)
            circles[i].layer?.cornerRadius = d / 2

            let labelX   = pad + d + lgap
            let labelMaxW = max(0, w - labelX - pad)
            let fontSize  = max(9, min(13, d * 0.38))
            let labelH: CGFloat = 15
            let labelY   = y + (d - labelH) / 2

            lblViews[i].frame  = NSRect(x: labelX, y: labelY, width: labelMaxW, height: labelH)
            lblViews[i].isHidden = !showL || labelMaxW < 20
            lblViews[i].font   = .systemFont(ofSize: fontSize, weight: .medium)
        }

        // grip at bottom-right
        grip?.frame = NSRect(x: w - hsz, y: 0, width: hsz, height: hsz)
        grip?.needsDisplay = true
    }

    // ── resize ─────────────────────────────────────────────────────

    private func handleResize(dx: CGFloat, dy: CGFloat) {
        guard let p = panel else { return }
        let showL = Preferences.shared.showFloatingLabels

        let minH: CGFloat = Self.minD * 3 + Self.circleGap * 2 + Self.pad * 2
        let minW: CGFloat = showL
            ? Self.pad + Self.minD + Self.labelGap + 20 + Self.pad
            : Self.pad + Self.minD + Self.pad

        var f = p.frame
        // dx > 0 → drag right → widen; dy < 0 → drag down → taller
        let newW = max(minW, f.width  + dx)
        let newH = max(minH, f.height - dy)  // dy<0 means pulled down → height grows
        let newY = f.origin.y + (f.height - newH)  // keep top fixed

        p.setFrame(NSRect(x: f.origin.x, y: newY, width: newW, height: newH), display: true)
        relayout()
        persist()
    }

    // ── persistence ────────────────────────────────────────────────

    private func persist() {
        guard let p = panel else { return }
        defaults.set(Double(p.frame.origin.x), forKey: kX)
        defaults.set(Double(p.frame.origin.y), forKey: kY)
        defaults.set(Double(p.frame.width),    forKey: kW)
        defaults.set(Double(p.frame.height),   forKey: kH)
    }

    @objc private func windowMoved(_ note: Notification) { persist() }

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

    private func defaultOrigin(size: NSSize) -> NSPoint {
        let sf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: sf.maxX - size.width - 24, y: sf.maxY - size.height - 24)
    }

    // ── helpers ────────────────────────────────────────────────────

    private func diameter(for windowHeight: CGFloat) -> CGFloat {
        let available = windowHeight - Self.pad * 2 - Self.circleGap * 2
        return max(Self.minD, min(Self.maxD, available / 3))
    }

    private func stateColor(_ state: AgentState) -> NSColor {
        switch state {
        case .idle:    return NSColor(white: 0.22, alpha: 1)
        case .running: return NSColor(red: 0.95, green: 0.78, blue: 0.00, alpha: 1)
        case .waiting: return NSColor(red: 0.90, green: 0.12, blue: 0.12, alpha: 1)
        case .done:    return NSColor(red: 0.12, green: 0.78, blue: 0.25, alpha: 1)
        case .error:   return NSColor(red: 0.58, green: 0.12, blue: 0.85, alpha: 1)
        }
    }
}
