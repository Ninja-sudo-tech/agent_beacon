import AppKit
import Core

// MARK: - Resize grip

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
        NSColor.white.withAlphaComponent(0.28).setStroke()
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

    // ── constants ────────────────────────────────────────────────────
    private static let pad:      CGFloat = 9
    private static let gap:      CGFloat = 8
    private static let minD:     CGFloat = 20
    private static let maxD:     CGFloat = 88
    private static let defaultD: CGFloat = 36
    private static let handleSz: CGFloat = 16

    private static func defaultSize() -> NSSize {
        let d = defaultD
        let h = d * 3 + gap * 2 + pad * 2
        let w = pad + d + pad
        return NSSize(width: w, height: h)
    }

    // ── state ────────────────────────────────────────────────────────
    private(set) var panel: NSPanel?
    private var bg: NSView?
    private var circles: [NSView]      = []
    private var lblViews: [NSTextField] = []
    private var grip: ResizeHandle?

    private let defaults = UserDefaults.standard
    private let kX = "ab.float.x", kY = "ab.float.y"
    private let kW = "ab.float.w", kH = "ab.float.h"

    var isVisible: Bool { panel?.isVisible ?? false }

    // ── public API ───────────────────────────────────────────────────

    func show() {
        if panel == nil { buildPanel() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Refresh label visibility after preference change — no resize needed.
    func applyLabelVisibility() {
        let show = Preferences.shared.showFloatingLabels
        lblViews.forEach { $0.isHidden = !show }
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
            }
        }
    }

    // ── build ────────────────────────────────────────────────────────

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
        p.isMovableByWindowBackground = true

        NotificationCenter.default.addObserver(self, selector: #selector(didMove(_:)),
            name: NSWindow.didMoveNotification, object: p)

        // Dark frosted-glass background
        let background = NSView(frame: p.contentView!.bounds)
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.72).cgColor
        background.layer?.masksToBounds   = true
        p.contentView?.addSubview(background)
        bg = background

        // Circles with centered labels
        let letters = ["C", "X", "A"]
        circles  = []
        lblViews = []
        let showL = Preferences.shared.showFloatingLabels

        for i in 0..<3 {
            // Colored circle
            let circle = NSView()
            circle.wantsLayer = true
            circle.layer?.masksToBounds   = true
            circle.layer?.backgroundColor = circleColor(.idle).cgColor
            // Glow: ambient shadow that pulses on active state
            circle.layer?.shadowColor   = NSColor.white.cgColor
            circle.layer?.shadowRadius  = 7
            circle.layer?.shadowOpacity = 0
            circle.layer?.shadowOffset  = .zero
            background.addSubview(circle)
            circles.append(circle)

            // Letter label — centered inside circle
            let lbl = NSTextField(labelWithString: letters[i])
            lbl.alignment       = .center
            lbl.textColor       = NSColor.white.withAlphaComponent(0.90)
            lbl.isBezeled       = false
            lbl.isEditable      = false
            lbl.drawsBackground = false
            lbl.isHidden        = !showL
            // Will be positioned/sized in relayout()
            circle.addSubview(lbl)
            lblViews.append(lbl)
        }

        // Resize grip
        let g = ResizeHandle()
        g.onDrag = { [weak self] dx, dy in self?.handleResize(dx: dx, dy: dy) }
        background.addSubview(g)
        grip = g

        panel = p
        relayout()
    }

    private func relayout() {
        guard let p = panel, let background = bg else { return }
        let w = p.frame.width
        let h = p.frame.height
        let pad  = Self.pad
        let gap  = Self.gap

        // Circle diameter scaled to window height
        let d = diameter(for: h)

        // Background pill — corner radius adapts to width/height
        background.frame = NSRect(x: 0, y: 0, width: w, height: h)
        background.layer?.cornerRadius = min(w, h) / 2.2

        // Vertical layout: circles centered
        let totalH = d * 3 + gap * 2
        let startY = (h - totalH) / 2
        let startX = (w - d) / 2  // horizontally centered

        // Font size proportional to diameter
        let fontSize = max(8, d * 0.42)

        for i in 0..<3 {
            guard i < circles.count, i < lblViews.count else { break }
            // i=0 → Claude (top) → highest y
            let y = startY + CGFloat(2 - i) * (d + gap)

            circles[i].frame = NSRect(x: startX, y: y, width: d, height: d)
            circles[i].layer?.cornerRadius = d / 2

            // Letter: centered in circle, auto-hide when circle too small
            let lh = fontSize + 3
            lblViews[i].frame = NSRect(x: 0, y: (d - lh) / 2, width: d, height: lh)
            lblViews[i].font  = .systemFont(ofSize: fontSize, weight: .bold)
            let showL = Preferences.shared.showFloatingLabels
            lblViews[i].isHidden = !showL || d < 22
        }

        // Grip at bottom-right of background
        grip?.frame = NSRect(x: w - Self.handleSz, y: 0,
                             width: Self.handleSz, height: Self.handleSz)
        grip?.needsDisplay = true
    }

    // ── resize ───────────────────────────────────────────────────────

    private func handleResize(dx: CGFloat, dy: CGFloat) {
        guard let p = panel else { return }
        let minH = Self.minD * 3 + Self.gap * 2 + Self.pad * 2
        let minW = Self.pad + Self.minD + Self.pad

        var f = p.frame
        let newW = max(minW, f.width  + dx)
        let newH = max(minH, f.height - dy)
        let newY = f.origin.y + (f.height - newH)

        p.setFrame(NSRect(x: f.origin.x, y: newY, width: newW, height: newH), display: true)
        relayout()
        persist()
    }

    // ── persistence ──────────────────────────────────────────────────

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

    // ── helpers ──────────────────────────────────────────────────────

    private func diameter(for windowHeight: CGFloat) -> CGFloat {
        let available = windowHeight - Self.pad * 2 - Self.gap * 2
        return max(Self.minD, min(Self.maxD, available / 3))
    }

    // Premium color palette — vivid but not garish
    private func circleColor(_ state: AgentState) -> NSColor {
        switch state {
        case .idle:    return NSColor(white: 0.18, alpha: 1)            // near-black
        case .running: return NSColor(red: 0.96, green: 0.76, blue: 0.00, alpha: 1)  // amber
        case .waiting: return NSColor(red: 0.92, green: 0.18, blue: 0.18, alpha: 1)  // crimson
        case .done:    return NSColor(red: 0.16, green: 0.80, blue: 0.36, alpha: 1)  // emerald
        case .error:   return NSColor(red: 0.62, green: 0.18, blue: 0.90, alpha: 1)  // violet
        }
    }
}
