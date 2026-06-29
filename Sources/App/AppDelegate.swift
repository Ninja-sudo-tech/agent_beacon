import AppKit
import Core

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private let store = StatusStore()
    private var fileWatcher: FileWatcher?
    private var statuses: [AgentStatus] = []
    private var doneTimers: [String: Timer] = [:]
    private let floating = FloatingWindowController()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.systemFont(ofSize: 13)
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        try? FileManager.default.createDirectory(
            at: store.statusDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        fileWatcher = FileWatcher(directory: store.statusDirectory) { [weak self] in
            self?.refreshStatuses()
        }

        // Restore visibility prefs
        applyMenuBarVisibility()
        if Preferences.shared.showFloating { floating.show() }

        refreshStatuses()
    }

    // MARK: - Status

    private func refreshStatuses() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statuses = self.store.readAll()
            self.updateMenuBarTitle()
            self.floating.updateStatuses(self.statuses)
            self.scheduleDoneTimersIfNeeded()
        }
    }

    // MARK: - Menu bar title

    private static let agentLabel: [String: String] = [
        "claude":      "Claude",
        "codex":       "Codex",
        "antigravity": "AGY"
    ]

    private func updateMenuBarTitle() {
        guard Preferences.shared.showMenuBar else { return }
        let indicators = knownAgents.map { agent -> String in
            let state = statuses.first(where: { $0.agent == agent })?.state ?? .idle
            let label = Self.agentLabel[agent] ?? agent
            return "\(state.menuBarEmoji)\(label)"
        }
        statusItem.button?.title = " " + indicators.joined(separator: "  ")
    }

    private func applyMenuBarVisibility() {
        statusItem.isVisible = Preferences.shared.showMenuBar
    }

    // MARK: - Done Auto-Transition

    private func scheduleDoneTimersIfNeeded() {
        let minutes = Preferences.shared.autoTransitionDoneMinutes
        guard minutes > 0 else { return }

        for status in statuses where status.state == .done {
            guard doneTimers[status.agent] == nil else { continue }
            let agent = status.agent
            let t = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                self?.doneTimers[agent] = nil
                let idle = AgentStatus(agent: agent, state: .idle, message: "Auto-reset", source: "timer")
                try? self?.store.write(idle)
                self?.refreshStatuses()
            }
            doneTimers[agent] = t
        }
        for (agent, timer) in doneTimers {
            if !statuses.contains(where: { $0.agent == agent && $0.state == .done }) {
                timer.invalidate()
                doneTimers[agent] = nil
            }
        }
    }

    // MARK: - Menu

    @objc private func statusItemClicked() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Title
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        titleItem.attributedTitle = NSAttributedString(
            string: "Agent Beacon",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        )
        menu.addItem(titleItem)
        menu.addItem(.separator())

        // Per-agent sections
        for status in statuses { addAgentSection(to: menu, status: status) }

        menu.addItem(.separator())

        // Global actions
        let resetAllItem = NSMenuItem(title: "全部设为空闲", action: #selector(resetAll), keyEquivalent: "")
        resetAllItem.target = self
        menu.addItem(resetAllItem)

        let openLogItem = NSMenuItem(title: "打开日志目录", action: #selector(openStatusDirectory), keyEquivalent: "")
        openLogItem.target = self
        menu.addItem(openLogItem)

        menu.addItem(.separator())

        // ── Display options ──
        let prefs = Preferences.shared

        let menuBarItem = NSMenuItem(title: "菜单栏图标", action: #selector(toggleMenuBar), keyEquivalent: "")
        menuBarItem.target = self
        menuBarItem.state  = prefs.showMenuBar ? .on : .off
        menu.addItem(menuBarItem)

        let floatItem = NSMenuItem(title: "桌面浮窗", action: #selector(toggleFloating), keyEquivalent: "")
        floatItem.target = self
        floatItem.state  = prefs.showFloating ? .on : .off
        menu.addItem(floatItem)

        menu.addItem(.separator())

        // done auto-transition
        let autoMinutes = prefs.autoTransitionDoneMinutes
        let autoLabel = autoMinutes > 0 ? "done 自动转 idle: \(autoMinutes) 分钟后 ✓" : "done 自动转 idle: 已禁用"
        let autoItem = NSMenuItem(title: autoLabel, action: #selector(toggleAutoTransition), keyEquivalent: "")
        autoItem.target = self
        menu.addItem(autoItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Agent Beacon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    private func addAgentSection(to menu: NSMenu, status: AgentStatus) {
        let displayName = agentDisplayNames[status.agent] ?? status.agent

        let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.attributedTitle = NSAttributedString(
            string: displayName,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(headerItem)

        let stateColor: NSColor
        switch status.state {
        case .idle:    stateColor = .secondaryLabelColor
        case .running: stateColor = NSColor(red: 0.9, green: 0.75, blue: 0, alpha: 1)
        case .waiting: stateColor = NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
        case .done:    stateColor = NSColor(red: 0.1, green: 0.75, blue: 0.25, alpha: 1)
        case .error:   stateColor = NSColor(red: 0.55, green: 0.1, blue: 0.8, alpha: 1)
        }

        let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        stateItem.attributedTitle = NSAttributedString(
            string: "\(status.state.emoji)  \(status.state.displayName)",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: stateColor]
        )
        menu.addItem(stateItem)

        if !status.message.isEmpty {
            let msgItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            msgItem.isEnabled = false
            msgItem.attributedTitle = NSAttributedString(
                string: "    \(status.message)",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]
            )
            menu.addItem(msgItem)
        }

        let timeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        timeItem.isEnabled = false
        timeItem.attributedTitle = NSAttributedString(
            string: "    更新于 \(status.formattedUpdateTime)",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.quaternaryLabelColor]
        )
        menu.addItem(timeItem)

        let idleItem = NSMenuItem(title: "    › 设为空闲", action: #selector(setAgentIdle(_:)), keyEquivalent: "")
        idleItem.target = self
        idleItem.representedObject = status.agent
        idleItem.isEnabled = status.state != .idle
        menu.addItem(idleItem)

        let openItem = NSMenuItem(title: "    › \(openActionLabel(for: status.agent))", action: #selector(openAgentApp(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = status.agent
        menu.addItem(openItem)

        menu.addItem(.separator())
    }

    private func openActionLabel(for agent: String) -> String {
        switch agent {
        case "claude":      return "打开终端 (Claude Code)"
        case "codex":       return "打开 Codex"
        case "antigravity": return "打开 Antigravity"
        default:            return "打开应用"
        }
    }

    // MARK: - Actions

    @objc private func setAgentIdle(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? String else { return }
        doneTimers[agent]?.invalidate()
        doneTimers[agent] = nil
        try? store.write(AgentStatus(agent: agent, state: .idle, message: "", source: "manual"))
        refreshStatuses()
    }

    @objc private func resetAll() {
        for agent in knownAgents {
            doneTimers[agent]?.invalidate()
            doneTimers[agent] = nil
            try? store.delete(agent: agent)
        }
        refreshStatuses()
    }

    @objc private func openAgentApp(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? String else { return }
        switch agent {
        case "claude":
            let script = """
            tell application "Terminal"
                activate
                do script "echo 'Claude Code — use CLI: claude'"
            end tell
            """
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        case "codex":
            NSWorkspace.shared.launchApplication("Codex")
        case "antigravity":
            NSWorkspace.shared.launchApplication("Antigravity")
        default: break
        }
    }

    @objc private func openStatusDirectory() {
        NSWorkspace.shared.open(store.statusDirectory)
    }

    @objc private func toggleAutoTransition() {
        let current = Preferences.shared.autoTransitionDoneMinutes
        switch current {
        case 0:  Preferences.shared.autoTransitionDoneMinutes = 5
        case 5:  Preferences.shared.autoTransitionDoneMinutes = 10
        case 10: Preferences.shared.autoTransitionDoneMinutes = 30
        default: Preferences.shared.autoTransitionDoneMinutes = 0
        }
    }

    @objc private func toggleMenuBar() {
        let prefs = Preferences.shared
        let next = !prefs.showMenuBar
        // Safety: can't hide both menu bar and floating window at the same time
        if !next && !prefs.showFloating {
            // Force-show floating window first
            prefs.showFloating = true
            floating.show()
        }
        prefs.showMenuBar = next
        applyMenuBarVisibility()
        if next { updateMenuBarTitle() }
    }

    @objc private func toggleFloating() {
        let prefs = Preferences.shared
        let next = !prefs.showFloating
        // Safety: can't hide both at the same time
        if !next && !prefs.showMenuBar {
            prefs.showMenuBar = true
            applyMenuBarVisibility()
            updateMenuBarTitle()
        }
        prefs.showFloating = next
        if next { floating.show(); floating.updateStatuses(statuses) }
        else     { floating.hide() }
    }
}
