import Foundation

public enum AgentState: String, Codable, CaseIterable, Equatable {
    case idle
    case running
    case waiting
    case done
    case error

    /// Higher value = higher display priority in menu bar icon selection
    public var priority: Int {
        switch self {
        case .idle:    return 0
        case .done:    return 1
        case .running: return 2
        case .waiting: return 3
        case .error:   return 4
        }
    }

    public var emoji: String {
        switch self {
        case .idle:    return "⚪"
        case .running: return "🟡"
        case .waiting: return "🔴"
        case .done:    return "🟢"
        case .error:   return "🟣"
        }
    }

    public var displayName: String {
        switch self {
        case .idle:    return "空闲"
        case .running: return "运行中"
        case .waiting: return "等待中"
        case .done:    return "已完成"
        case .error:   return "错误"
        }
    }

    public var menuBarEmoji: String {
        switch self {
        case .idle:    return "⚪"
        case .running: return "🟡"
        case .waiting: return "🔴"
        case .done:    return "🟢"
        case .error:   return "🟣"
        }
    }
}

public struct AgentStatus: Codable, Equatable {
    public var agent: String
    public var state: AgentState
    public var message: String
    public var updatedAt: String
    public var source: String

    public init(
        agent: String,
        state: AgentState,
        message: String = "",
        source: String = "manual"
    ) {
        self.agent = agent
        self.state = state
        self.message = message
        self.updatedAt = ISO8601DateFormatter().string(from: Date())
        self.source = source
    }

    public var updatedAtDate: Date? {
        ISO8601DateFormatter().date(from: updatedAt)
    }

    public var formattedUpdateTime: String {
        guard let date = updatedAtDate else { return updatedAt }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}

public let knownAgents: [String] = ["claude", "codex", "antigravity"]

public let agentDisplayNames: [String: String] = [
    "claude":      "Claude",
    "codex":       "Codex",
    "antigravity": "Antigravity"
]

public let agentAppBundleIDs: [String: String] = [
    "claude":      "com.anthropic.claudefordesktop",
    "codex":       "com.openai.codex",
    "antigravity": "com.google.Antigravity"
]

/// Returns the highest-priority state across all statuses.
public func dominantState(from statuses: [AgentStatus]) -> AgentState {
    statuses.map(\.state).max(by: { $0.priority < $1.priority }) ?? .idle
}
