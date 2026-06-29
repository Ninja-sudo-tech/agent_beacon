import AppKit
import Core

// MARK: - Size presets

struct FloatingSizePreset {
    let key:      String
    let label:    String
    let d:        CGFloat   // circle diameter
    let labelW:   CGFloat   // label column width

    private static let pad:      CGFloat = 9
    private static let gap:      CGFloat = 8
    private static let labelGap: CGFloat = 10

    var height: CGFloat { d * 3 + Self.gap * 2 + Self.pad * 2 }
    var widthWithLabels: CGFloat { Self.pad + d + Self.labelGap + labelW + Self.pad }
    var widthNoLabels:   CGFloat { Self.pad + d + Self.pad }
    var fontSize: CGFloat { max(9, d * 0.38) }

    static let small  = FloatingSizePreset(key: "small",  label: "小", d: 22, labelW: 44)
    static let medium = FloatingSizePreset(key: "medium", label: "中", d: 34, labelW: 62)
    static let large  = FloatingSizePreset(key: "large",  label: "大", d: 50, labelW: 88)
    static let all    = [small, medium, large]

    static func forKey(_ key: String) -> FloatingSizePreset {
        all.first(where: { $0.key == key }) ?? .medium
    }
}

// MARK: - Background view (move + right-click only)

private final class FloatingBackground: NSView {
    var onMove:       ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onRightClick: ((_ screenPt: NSPoint) -> Void)?

    private var startScreen: NSPoint = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        startScreen = w.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let cur = w.convertPoint(toScreen: event.locationInWindow)
        onMove?(cur.x - startScreen.x, cur.y - startScreen.y)
        startScreen = cur
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let w = window else { return }
        onRightClick?(w.convertPoint(toScreen: event.locationInWindow))
    }
}

// MARK: - Controller

final class FloatingWindowController: NSObject {

    private static let pad:      CGFloat = 9
    private static let gap:      CGFloat = 8
    private static let labelGap: CGFloat = 10

    // ── State ──────────────────────────────────────────────────────
    private(set) var panel: NSPanel?
    private var bgView:  FloatingBackground?
    private var circles: [NSView]       = []
    private var lblViews:[NSTextField]  = []

    var onShowMenu: ((NSPoint) -> Void)?

    private let defaults = UserDefaults.standard
    private let kX = "ab.float.x", kY = "ab.float.y"

    var isVisible: Bool { panel?.isVisible ?? false }

    // ── Public API ─────────────────────────────────────────────────

    func show() {
        if panel == nil { buildPanel() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Apply current size preset and label visibility — call after any pref change.
    func applyCurrentSize() {
        guard let p = panel else { return }
        let preset = FloatingSizePreset.forKey(Preferences.shared.floatingSize)
        let showL  = Preferences.shared.showFloatingLabels
        let sz = NSSize(
            width:  showL ? preset.widthWithLabels : preset.widthNoLabels,
            height: preset.height
        )
        var f = p.frame
        // Anchor top-left: keep top edge fixed as size changes
        f.origin.y += f.height - sz.height
        f.size = sz
        p.setFrame(f, display: true)
        relayout()
        persist()
    }

    /// Convenience — call when label toggle changes.
    func applyLabelVisibility() { applyCurrentSize() }

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

    // ── Build ───────────────────────────────────────────────────────

    private func buildPanel() {
        let preset = FloatingSizePreset.forKey(Preferences.shared.floatingSize)
        let showL  = Preferences.shared.showFloatingLabels
        let sz     = NSSize(
            width:  showL ? preset.widthWithLabels : preset.widthNoLabels,
            height: preset.height
        )
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
        bg.onRightClick = { [weak self] pt in self?.onShowMenu?(pt) }

        // Circles + labels
        let names = ["Claude", "Codex", "Antigr"]
        circles  = []
        lblViews = []

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

    // ── Layout ──────────────────────────────────────────────────────

    private func relayout() {
        guard let p = panel, let bg = bgView else { return }
        let w = p.frame.width
        let h = p.frame.height

        let preset = FloatingSizePreset.forKey(Preferences.shared.floatingSize)
        let showL  = Preferences.shared.showFloatingLabels
        let d      = preset.d
        let gap    = Self.gap
        let pad    = Self.pad
        let lgap   = Self.labelGap
        let font   = NSFont.systemFont(ofSize: preset.fontSize, weight: .semibold)

        bg.frame = NSRect(x: 0, y: 0, width: w, height: h)
        // Pill when narrow, rounded rect when labels visible
        bg.layer?.cornerRadius = showL ? 12 : (d / 2 + pad)

        let totalH = d * 3 + gap * 2
        let startY = (h - totalH) / 2
        let circleX = pad   // always left-aligned

        let labelX = pad + d + lgap
        let labelW = max(0, w - labelX - pad)

        for i in 0..<3 {
            guard i < circles.count, i < lblViews.count else { break }
            let cy = startY + CGFloat(2 - i) * (d + gap)

            circles[i].frame = NSRect(x: circleX, y: cy, width: d, height: d)
            circles[i].layer?.cornerRadius = d / 2

            let textH = (lblViews[i].stringValue as NSString)
                .size(withAttributes: [.font: font]).height
            let labelY = cy + (d - textH) / 2

            lblViews[i].frame    = NSRect(x: labelX, y: labelY, width: labelW, height: textH + 2)
            lblViews[i].font     = font
            lblViews[i].isHidden = !showL || labelW < 10
        }
    }

    // ── Persistence ─────────────────────────────────────────────────

    private func persist() {
        guard let p = panel else { return }
        defaults.set(Double(p.frame.origin.x), forKey: kX)
        defaults.set(Double(p.frame.origin.y), forKey: kY)
    }

    @objc private func didMove(_ n: Notification) { persist() }

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

    // ── Colors ──────────────────────────────────────────────────────

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
