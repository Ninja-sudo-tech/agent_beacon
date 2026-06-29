// Standalone test runner — no XCTest dependency (CLT environment)
import Foundation

// MARK: - Minimal test harness

var passed = 0
var failed = 0

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: String = #file, line: Int = #line
) {
    if condition() {
        print("  ✓ \(message)")
        passed += 1
    } else {
        print("  ✗ FAIL: \(message)  [\((file as NSString).lastPathComponent):\(line)]")
        failed += 1
    }
}

func test(_ name: String, body: () throws -> Void) {
    print("\n[\(name)]")
    do { try body() }
    catch { print("  ✗ THREW: \(error)"); failed += 1 }
}

// MARK: - AgentState tests

test("Priority ordering") {
    expect(AgentState.idle.priority    < AgentState.done.priority,    "idle < done")
    expect(AgentState.done.priority    < AgentState.running.priority, "done < running")
    expect(AgentState.running.priority < AgentState.waiting.priority, "running < waiting")
    expect(AgentState.waiting.priority < AgentState.error.priority,   "waiting < error")
}

test("Dominant state — error wins") {
    let statuses: [AgentStatus] = [
        AgentStatus(agent: "claude", state: .running),
        AgentStatus(agent: "codex",  state: .error),
        AgentStatus(agent: "antigravity", state: .idle)
    ]
    expect(dominantState(from: statuses) == .error, "error dominates running+idle")
}

test("Dominant state — waiting over running") {
    let statuses: [AgentStatus] = [
        AgentStatus(agent: "claude", state: .running),
        AgentStatus(agent: "codex",  state: .waiting),
        AgentStatus(agent: "antigravity", state: .done)
    ]
    expect(dominantState(from: statuses) == .waiting, "waiting dominates running+done")
}

test("Dominant state — all idle") {
    let statuses: [AgentStatus] = knownAgents.map { AgentStatus(agent: $0, state: .idle) }
    expect(dominantState(from: statuses) == .idle, "all idle → idle")
}

test("Dominant state — empty list") {
    expect(dominantState(from: []) == .idle, "empty → idle")
}

test("Emoji assignments") {
    expect(AgentState.idle.emoji    == "⚪", "idle emoji")
    expect(AgentState.running.emoji == "🟡", "running emoji")
    expect(AgentState.waiting.emoji == "🔴", "waiting emoji")
    expect(AgentState.done.emoji    == "🟢", "done emoji")
    expect(AgentState.error.emoji   == "🟣", "error emoji")
}

test("JSON round-trip all states") {
    for state in AgentState.allCases {
        let status = AgentStatus(agent: "test", state: state, message: "msg")
        guard let data = try? JSONEncoder().encode(status),
              let decoded = try? JSONDecoder().decode(AgentStatus.self, from: data)
        else {
            expect(false, "encode/decode failed for \(state)")
            continue
        }
        expect(decoded.state == state,   "state round-trip: \(state)")
        expect(decoded.agent == "test",  "agent round-trip: \(state)")
        expect(decoded.message == "msg", "message round-trip: \(state)")
    }
}

test("JSON field names — exactly 5 required fields") {
    let status = AgentStatus(agent: "codex", state: .waiting, message: "test", source: "cli")
    let data = try JSONEncoder().encode(status)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    expect(dict["agent"]     != nil, "has 'agent'")
    expect(dict["state"]     != nil, "has 'state'")
    expect(dict["message"]   != nil, "has 'message'")
    expect(dict["updatedAt"] != nil, "has 'updatedAt'")
    expect(dict["source"]    != nil, "has 'source'")
    expect(dict.count == 5,          "exactly 5 fields (got \(dict.count))")
}

// MARK: - StatusStore tests

test("StatusStore — write and read") {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ABTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = StatusStore(testDirectory: dir)
    let s = AgentStatus(agent: "claude", state: .running, message: "hello")
    try store.write(s)
    let r = store.read(agent: "claude")
    expect(r != nil,               "read returns non-nil")
    expect(r?.state == .running,   "state preserved")
    expect(r?.message == "hello",  "message preserved")
}

test("StatusStore — atomic write (10 rapid writes)") {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ABTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = StatusStore(testDirectory: dir)
    for i in 0..<10 {
        let s = AgentStatus(agent: "claude", state: .running, message: "iter \(i)")
        try store.write(s)
    }
    let r = store.read(agent: "claude")
    expect(r?.message == "iter 9", "last write wins: \(r?.message ?? "nil")")
}

test("StatusStore — read missing returns nil") {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ABTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = StatusStore(testDirectory: dir)
    expect(store.read(agent: "ghost") == nil, "missing agent → nil")
}

test("StatusStore — delete") {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ABTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = StatusStore(testDirectory: dir)
    try store.write(AgentStatus(agent: "codex", state: .done))
    expect(store.read(agent: "codex") != nil, "exists after write")
    try store.delete(agent: "codex")
    expect(store.read(agent: "codex") == nil,  "nil after delete")
}

test("StatusStore — readAll fills idle defaults") {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ABTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = StatusStore(testDirectory: dir)
    let all = store.readAll()
    expect(all.count == 3,                "3 agents returned")
    expect(all.allSatisfy { $0.state == .idle }, "all default to idle")
}

test("StatusStore — no sensitive keys in JSON") {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ABTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = StatusStore(testDirectory: dir)
    try store.write(AgentStatus(agent: "claude", state: .running, message: "ok"))
    let url = store.statusURL(for: "claude")
    let data = try Data(contentsOf: url)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let forbidden = ["prompt", "command", "env", "token", "key", "cookie", "password"]
    for key in forbidden {
        expect(dict[key] == nil, "no '\(key)' in JSON")
    }
}

// MARK: - Summary

print("\n" + String(repeating: "─", count: 40))
print("Results: \(passed) passed, \(failed) failed")
if failed > 0 {
    print("TESTS FAILED")
    exit(1)
} else {
    print("ALL TESTS PASSED ✓")
}
