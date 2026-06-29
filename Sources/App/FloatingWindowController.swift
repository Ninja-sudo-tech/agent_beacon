import AppKit
import Core

final class FloatingWindowController: NSObject {

    // MARK: - Layout constants
    private static let diameter: CGFloat  = 34
    private static let gap:      CGFloat  = 8
    private static let padding:  CGFloat  = 9
    static var panelW: CGFloat { diameter + padding * 2 }
    static var panelH: CGFloat { diameter * 3 + gap * 2 + padding * 2 }

    // MARK: - State
    private(set) var panel: NSPanel?
    private var circles: [NSView] = []   // index 0=claude 1=codex 2=antigravity

    private let defaults  = UserDefaults.standard
    private let kPosX     = "agentbeacon.float.x"
    private let kPosY     = "agentbeacon.float.y"

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Public API

    func show() {
        if panel == nil { buildPanel() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func updateStatuses(_ statuses: [AgentStatus]) {
        guard let p = panel, p.isVisible else { return }
        let agents = ["claude", "codex", "antigravity"]
        for (i, agent) in agents.enumerated() {
            guard i < circles.count else { break }
            let state = statuses.first(where: { $0.agent == agent })?.state ?? .idle
            circles[i].layer?.backgroundColor = color(for: state).cgColor
            circles[i].layer?.shadowOpacity   = state == .idle ? 0 : 0.7
        }
    }

    // MARK: - Build

    private func savedOrigin() -> NSPoint? {
        let x = defaults.double(forKey: kPosX)
        let y = defaults.double(forKey: kPosY)
        guard x != 0 || y != 0 else { return nil }
        // Clamp to visible screen
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            if sf.contains(NSPoint(x: x, y: y)) { return NSPoint(x: x, y: y) }
        }
        return nil
    }

    private func buildPanel() {
        let w = Self.panelW
        let h = Self.panelH
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defaultOrigin = NSPoint(x: screen.maxX - w - 24, y: screen.maxY - h - 24)
        let origin = savedOrigin() ?? defaultOrigin

        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: w, height: h)),
            styleMask:   [.nonactivatingPanel, .borderless],
            backing:     .buffered,
            defer:       false
        )
        p.level                = .floating
        p.collectionBehavior   = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isOpaque             = false
        p.backgroundColor      = .clear
        p.hasShadow            = true
        p.isMovableByWindowBackground = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove(_:)),
            name: NSWindow.didMoveNotification, object: p
        )

        // Background pill
        let bg = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.wantsLayer = true
        bg.layer?.backgroundColor  = NSColor.black.withAlphaComponent(0.52).cgColor
        bg.layer?.cornerRadius     = w / 2
        bg.layer?.masksToBounds    = true
        p.contentView = bg

        // Three circles
        let d   = Self.diameter
        let sp  = Self.gap
        let pad = Self.padding
        circles = []
        for i in 0..<3 {
            let y = h - pad - d - CGFloat(i) * (d + sp)
            let v = NSView(frame: NSRect(x: pad, y: y, width: d, height: d))
            v.wantsLayer = true
            v.layer?.cornerRadius    = d / 2
            v.layer?.masksToBounds   = true
            v.layer?.backgroundColor = color(for: .idle).cgColor
            // glow
            v.layer?.shadowColor   = NSColor.white.cgColor
            v.layer?.shadowRadius  = 5
            v.layer?.shadowOpacity = 0
            v.layer?.shadowOffset  = .zero
            bg.addSubview(v)
            circles.append(v)
        }

        panel = p
    }

    @objc private func didMove(_ note: Notification) {
        guard let w = note.object as? NSWindow else { return }
        defaults.set(Double(w.frame.origin.x), forKey: kPosX)
        defaults.set(Double(w.frame.origin.y), forKey: kPosY)
    }

    // MARK: - Colors (same scale as AppDelegate menu colors)

    private func color(for state: AgentState) -> NSColor {
        switch state {
        case .idle:    return NSColor(white: 0.22, alpha: 1)
        case .running: return NSColor(red: 0.95, green: 0.78, blue: 0.00, alpha: 1)
        case .waiting: return NSColor(red: 0.90, green: 0.12, blue: 0.12, alpha: 1)
        case .done:    return NSColor(red: 0.12, green: 0.78, blue: 0.25, alpha: 1)
        case .error:   return NSColor(red: 0.58, green: 0.12, blue: 0.85, alpha: 1)
        }
    }
}
