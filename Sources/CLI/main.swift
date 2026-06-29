import Foundation
import Core

// MARK: - Usage

func printUsage() {
    let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "agent-beacon"
    print("""
    Agent Beacon CLI v1.0

    Usage:
      \(prog) set <agent> <state> [message]
      \(prog) reset <agent|all>
      \(prog) list
      \(prog) help

    Agents:  claude | codex | antigravity
    States:  idle | running | waiting | done | error

    Examples:
      \(prog) set claude running "正在处理任务"
      \(prog) set codex waiting "等待权限确认"
      \(prog) set antigravity done "任务完成"
      \(prog) reset claude
      \(prog) reset all
      \(prog) list
    """)
}

// MARK: - Helpers

func exit(message: String, code: Int32 = 1) -> Never {
    fputs("agent-beacon: \(message)\n", stderr)
    Foundation.exit(code)
}

func validateAgent(_ agent: String) {
    guard knownAgents.contains(agent) else {
        exit(message: "unknown agent '\(agent)'. Valid: \(knownAgents.joined(separator: ", "))")
    }
}

func validateState(_ raw: String) -> AgentState {
    guard let state = AgentState(rawValue: raw) else {
        let valid = AgentState.allCases.map(\.rawValue).joined(separator: ", ")
        exit(message: "unknown state '\(raw)'. Valid: \(valid)")
    }
    return state
}

// MARK: - Commands

let store = StatusStore()
let args = CommandLine.arguments.dropFirst()

guard let command = args.first else {
    printUsage()
    Foundation.exit(0)
}

switch command {

case "help", "--help", "-h":
    printUsage()
    Foundation.exit(0)

case "set":
    let remaining = Array(args.dropFirst())
    guard remaining.count >= 2 else {
        exit(message: "set requires <agent> <state> [message]")
    }
    let agentName = remaining[0].lowercased()
    let stateName = remaining[1].lowercased()
    let message = remaining.count >= 3 ? remaining[2...].joined(separator: " ") : ""

    validateAgent(agentName)
    let state = validateState(stateName)

    let status = AgentStatus(
        agent: agentName,
        state: state,
        message: message,
        source: ProcessInfo.processInfo.environment["AGENT_BEACON_SOURCE"] ?? "cli"
    )
    do {
        try store.write(status)
        let displayName = agentDisplayNames[agentName] ?? agentName
        print("✓ \(displayName) → \(state.emoji) \(state.displayName)" + (message.isEmpty ? "" : ": \(message)"))
    } catch {
        exit(message: "failed to write status: \(error)")
    }

case "reset":
    let remaining = Array(args.dropFirst())
    guard let target = remaining.first else {
        exit(message: "reset requires <agent|all>")
    }
    if target == "all" {
        for agent in knownAgents {
            try? store.delete(agent: agent)
            let displayName = agentDisplayNames[agent] ?? agent
            print("✓ \(displayName) → ⚪ 空闲")
        }
    } else {
        let agentName = target.lowercased()
        validateAgent(agentName)
        do {
            try store.delete(agent: agentName)
            let displayName = agentDisplayNames[agentName] ?? agentName
            print("✓ \(displayName) → ⚪ 空闲")
        } catch {
            exit(message: "failed to reset: \(error)")
        }
    }

case "list":
    let statuses = store.readAll()
    print("Agent Beacon 状态:")
    print(String(repeating: "─", count: 50))
    for status in statuses {
        let displayName = (agentDisplayNames[status.agent] ?? status.agent).padding(toLength: 14, withPad: " ", startingAt: 0)
        let stateLabel = "\(status.state.emoji) \(status.state.displayName)".padding(toLength: 12, withPad: " ", startingAt: 0)
        let timeStr = status.formattedUpdateTime
        let msgPart = status.message.isEmpty ? "" : "  \"\(status.message)\""
        print("  \(displayName)  \(stateLabel)  @\(timeStr)\(msgPart)")
    }
    print(String(repeating: "─", count: 50))
    let dominant = dominantState(from: statuses)
    print("总体状态: \(dominant.emoji) \(dominant.displayName)")

default:
    printUsage()
    exit(message: "unknown command '\(command)'")
}
