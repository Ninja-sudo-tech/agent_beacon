import Foundation

public final class StatusStore {
    public static let shared = StatusStore()

    public let statusDirectory: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        statusDirectory = home
            .appendingPathComponent(".agent-beacon")
            .appendingPathComponent("status")
        try? FileManager.default.createDirectory(
            at: statusDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Initializer for testing — use a custom directory instead of ~/.agent-beacon/status
    public init(testDirectory: URL) {
        statusDirectory = testDirectory
        try? FileManager.default.createDirectory(
            at: statusDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public func statusURL(for agent: String) -> URL {
        statusDirectory.appendingPathComponent("\(agent).json")
    }

    /// Atomically writes status to disk.
    public func write(_ status: AgentStatus) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(status)

        let url = statusURL(for: status.agent)
        // Write to a temp file first, then rename (atomic)
        let tmpURL = statusDirectory.appendingPathComponent(".\(status.agent).tmp")
        try data.write(to: tmpURL, options: [])
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
    }

    /// Reads a single agent status. Returns nil if file missing or malformed.
    public func read(agent: String) -> AgentStatus? {
        let url = statusURL(for: agent)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentStatus.self, from: data)
    }

    /// Reads all known agents. Missing files are returned as idle.
    public func readAll() -> [AgentStatus] {
        knownAgents.map { agent in
            read(agent: agent) ?? AgentStatus(agent: agent, state: .idle, source: "default")
        }
    }

    /// Deletes the status file for an agent (effectively resetting to idle).
    public func delete(agent: String) throws {
        let url = statusURL(for: agent)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
