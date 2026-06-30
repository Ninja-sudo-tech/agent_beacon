# Agent Beacon

macOS 菜单栏应用，同时显示 Claude Code、Codex 和 Antigravity 的任务状态。  
全程静音，不显示 Dock 图标，不使用系统通知。

---

## 目录结构

```
agent_beacon/
├── Sources/
│   ├── Core/                       # 共享状态模型和文件存储
│   ├── CLI/                        # agent-beacon CLI 工具
│   └── App/                        # AppKit MenuBar 应用
│       ├── AppDelegate.swift       # 菜单栏、菜单逻辑
│       ├── FloatingWindowController.swift  # 桌面浮窗（NSPanel）
│       ├── FileWatcher.swift       # kqueue 文件监听
│       └── Preferences.swift       # UserDefaults 封装
├── Tests/                          # 独立测试套件 (50 项测试)
├── Resources/                      # Info.plist、LaunchAgent plists
├── Wrappers/                       # Claude/Codex hook 脚本 + AGY 日志监听守护进程
│   ├── agent-gemini-watcher        # Antigravity 状态自动检测（日志监听）
│   ├── agent-claude-watcher        # Claude Code 状态自动检测（会话记录监听）
│   └── agent-codex-watcher         # Codex 状态自动检测（会话记录监听）
└── Scripts/                        # build、install、uninstall、setup-hooks
```

---

## 快速开始

```bash
# 1. 构建
bash Scripts/build.sh

# 2. 安装
bash Scripts/install.sh      # 需要 sudo（安装到 /usr/local/bin）
# 或用户目录安装（无需 sudo）：
mkdir -p ~/.local/bin
cp .build/agent-beacon ~/.local/bin/
cp Wrappers/agent-codex ~/.local/bin/
cp Wrappers/agent-beacon-claude-notify ~/.local/bin/

# 3. 配置 hooks
bash Scripts/setup-hooks.sh

# 4. 启动 App
open /Applications/AgentBeacon.app
```

---

## CLI 用法

```bash
agent-beacon set claude running "正在处理任务"
agent-beacon set claude waiting "等待权限确认"
agent-beacon set claude done "任务完成"
agent-beacon set codex running "正在处理任务"
agent-beacon set antigravity waiting "等待输入"
agent-beacon reset claude
agent-beacon reset all
agent-beacon list
```

---

## 状态说明

| 状态    | 颜色 | Emoji | 优先级 |
|---------|------|-------|--------|
| idle    | 灰色 | ⚪    | 0 (最低) |
| done    | 绿色 | 🟢    | 1 |
| running | 黄色 | 🟡    | 2 |
| waiting | 红色 | 🔴    | 3 |
| error   | 紫色 | 🟣    | 4 (最高) |

菜单栏现在为**每个 Agent 显示独立的指示灯**（不再是单一合并图标）：
```
⚪Claude  🟡Codex  🔴Antigr
```
点击图标打开下拉菜单，可查看每个 Agent 的详细状态、消息和更新时间。

---

## 桌面浮窗

菜单 → **桌面浮窗** 开启后，桌面上会出现一个半透明、置顶、可拖动的小窗口，三个圆形指示灯代表三个 Agent。

**特性：**
- 默认竖向排列（Claude / Codex / Antigr 上下堆叠），可在菜单切换为**横向排列**
- 5 档固定大小：小 / 中 / 大 / 超大 / 超超大（菜单 → 桌面浮窗 → 大小）
- 字号随圆形直径等比缩放，标签可显示/隐藏（菜单 → 显示标签）
- 跨所有 Space 保持可见，不抢焦点，不出现在 Dock 或 Cmd+Tab 中
- 拖动任意位置移动；位置自动记忆，重启后恢复
- **右键单击浮窗** 弹出完整设置菜单 — 当菜单栏图标被隐藏时，这是找回控制入口的方式

**安全机制：** 菜单栏图标和桌面浮窗不能同时关闭。关闭其中一个时，若另一个也处于关闭状态，会自动开启另一个，避免彻底失去控制入口。

---

## 状态文件

所有状态存储在 `~/.agent-beacon/status/`，每个 Agent 一个 JSON 文件：

```json
{
  "agent": "claude",
  "state": "running",
  "message": "正在处理任务",
  "updatedAt": "2026-06-29T08:00:00Z",
  "source": "hook"
}
```

- 字段严格为 5 个，不含提示词、命令、环境变量、密钥等敏感信息
- 写入使用原子操作（写临时文件后 rename），避免读取半成品 JSON
- 菜单栏应用使用 `kqueue` 文件系统监听，**不轮询**

---

## Claude Code 集成

**版本：** Claude Code 2.1.133  
**集成方式：** `~/.claude/settings.json` hooks

已配置以下 hooks（Claude Code 2.1.133 实测确认支持）：

| 事件 | 触发条件 | 状态变化 | 执行方式 |
|------|----------|----------|----------|
| `UserPromptSubmit` | 用户提交提示词 | → `running` ✅ | 后台异步 |
| `PreToolUse` / `PostToolUse` | 工具调用前/后 | → `running` ✅ | 后台异步 |
| `PermissionRequest` | Claude 需要权限执行工具时弹出确认框 | → `waiting` ✅ | 同步 |
| `Stop` | 会话结束 | → `done` ✅ | 后台异步 |

**`PermissionRequest` 是 Claude Code 的原生专用 hook**，当 Claude 需要执行一个未预授权的工具（如 Bash 命令）时精确触发，无需关键词猜测。

**黄→红→黄 完整链路：** `UserPromptSubmit`（🟡）→ 弹出权限确认（🔴 `PermissionRequest`）→ 用户批准、工具执行完毕（🟡 `PostToolUse`）→ 会话结束（🟢 `Stop`）。

**性能优化：** `UserPromptSubmit`/`Stop`/`PostToolUse` 均以 `(cat>/dev/null; agent-beacon ...) &` 形式后台执行，Claude Code 无需等待 hook 进程退出即可继续工作，避免每次工具调用产生 100-200ms 延迟。`PermissionRequest` 保持同步执行（此时 Claude 本就在等待用户输入，无延迟影响）。

> 早期版本曾使用 `Notification` hook 做关键词猜测来检测等待状态，但会对 Claude 的常规系统通知（更新提示等）产生误判，已移除。

### 拒绝权限后红灯卡死的修复

**问题：** 用户拒绝权限请求后（无论是单纯拒绝，还是拒绝并输入自定义反馈），Claude 会继续生成文字或尝试其他方案，但 hook 系统里**没有任何事件**能捕捉"助手正在生成文本"这件事——`PreToolUse`/`PostToolUse` 只在工具调用时触发，拒绝意味着工具根本没执行，因此不会触发。`UserPromptSubmit` 只在用户主动输入新提示词时触发。结果是红灯会一直卡住，直到 `Stop` 才变绿，期间完全无法反映 Claude 实际仍在工作。

**修复：** Claude Code 会把每一轮对话实时写入：
```
~/.claude/projects/<project-slug>/<session-id>.jsonl
```
`agent-claude-watcher`（Python 守护进程）持续追踪**全部项目中最近被修改的会话文件**，每当看到新的 `"type":"assistant"` 条目出现，立即将状态设为 `running`——这是 hooks 之外的补充信号，专门填补"拒绝后 Claude 继续工作但无 hook 可用"的空白。

**守护进程部署：**
```
~/.local/bin/agent-claude-watcher
~/Library/LaunchAgents/com.agentbeacon.claude-watcher.plist   # KeepAlive=true
```

**注意：** 该 watcher 只会跟踪全局最近修改的会话文件，因此无法区分同时运行的多个 Claude Code 会话（不同终端/不同项目）——这与单一指示灯本身无法表示多会话状态的限制一致。

**IDE 集成状态：**  
- ✅ Claude Code CLI：hooks 通过 settings.json 生效
- ⚠️ JetBrains/VS Code 集成：读取同一 settings.json，hooks **应该**生效，但需实测验证
- ❓ Claude Code Desktop：是否执行 settings.json hooks 需实测（桌面版可能有独立配置）

---

## Codex 集成

**版本：** Codex CLI 0.142.2  
**集成方式：** `~/.codex/hooks.json`（主要）+ `config.toml notify`（兜底）

### hooks.json（推荐，支持交互终端 + exec 模式）

Codex 支持与 Claude Code 相同的 hook 事件系统，通过 `~/.codex/hooks.json` 配置。

已实测确认 Codex 0.142.2 支持的事件：

| 事件 | 触发条件 | 状态变化 |
|------|----------|----------|
| `UserPromptSubmit` | 用户在终端中提交提示词 | → `running` ✅ |
| `PermissionRequest` | Codex 请求执行权限 | → `waiting` ✅ |
| `Stop` | 会话结束 | → `done` ✅ |

**注意：首次在 Codex 终端使用时，会出现 hook 信任确认对话框：**
```
Hooks need review
1 hook is new or changed.
→ Trust all and continue        ← 选这个
→ Continue without trusting (hooks won't run)
```
选择信任后，哈希会持久化到本地，之后所有会话（包括 PyCharm 等 IDE 内置终端）自动生效，无需重复确认。

**静默运行：** 每个 hook 命令都会把 `agent-beacon` 的输出重定向到 `/dev/null`，并返回 `{"suppressOutput": true}` —— 这是 Codex hook 的标准 JSON 响应字段，告诉 Codex 不要在聊天框里显示 hook 执行结果，做到完全无感运行。

### config.toml notify（兜底机制）

同时保留 `notify` 字段作为兜底，即使 hooks.json 未被信任，turn 结束时仍会触发 `done`：
```
turn-ended → done
```
原始 Codex Computer Use 客户端被封装保留。

### codex exec 测试结果

```
codex exec --json "..." < /dev/null
```
时间线实测：
- 提交提示 → `running`（约 2s 后 hook 触发）
- 回答完成 → `done`（notify 触发）

**Codex Desktop 状态：**  
- ✅ `notify` hook：config.toml 已更新，Desktop 应读取同一配置
- ✅ `hooks.json`：Desktop App 与 CLI 共享 `~/.codex/`，应生效（需实测）
- 首次使用需在 Desktop 中通过信任对话框

### 拒绝权限后红灯卡死的修复（与 Claude Code 相同的问题）

排查发现 Codex 和 Claude Code 共享同一套 hook 事件集合（`PreToolUse` / `PostToolUse` / `PermissionRequest` / `UserPromptSubmit` / `Stop` 等），因此存在**完全相同的缺陷**：用户拒绝一个 exec/patch 审批请求后，工具不会执行，`PostToolUse` 不会触发；Codex 转而继续生成文字或尝试别的方案时，没有任何 hook 能捕捉这个"恢复工作"的时刻，红灯会一直卡到 `Stop` 才变绿。

**修复：** Codex CLI 会把每个会话实时写入：
```
~/.codex/sessions/<年>/<月>/<日>/rollout-<时间戳>-<id>.jsonl
```
确认了里面的 `response_item` 条目在 `payload.role == "assistant"` 时，正是 Codex 产出内容的直接证据（与 Claude Code 的 `type:"assistant"` 条目结构高度一致）。`agent-codex-watcher` 持续追踪全部会话中最近修改的那个文件，一旦出现新的 assistant 条目就立即设为 `running`。

**守护进程部署：**
```
~/.local/bin/agent-codex-watcher
~/Library/LaunchAgents/com.agentbeacon.codex-watcher.plist   # KeepAlive=true
```

---

## Antigravity 集成

**版本：** Antigravity Desktop App（Electron + Go 语言服务器）  
**自动集成：** ✅ 通过日志监听实现，**无需官方 API**

Antigravity 没有公开的 CLI hooks 或事件订阅接口，但其 CLI 后端会把详细的结构化日志写入：
```
~/.gemini/antigravity-cli/cli.log   （symlink，始终指向最新会话日志）
```

`agent-gemini-watcher`（Python 守护进程）实时 tail 这个文件，根据日志行精确识别状态：

| 日志特征 | 状态变化 |
|----------|----------|
| `Forwarding user message to conversation` | → `running` |
| `streamGenerateContent?alt=sse`（模型生成中，每次出现重置 4s 计时器） | → `running` |
| `Surfacing tool confirmation`（弹出工具确认框） | → `waiting` |
| `Responding to tool confirmation ... approved=true` | → `running`（工具即将执行）|
| `Responding to tool confirmation ... approved=false` | → `done`（用户拒绝，模型不再生成回复，**立即**触发）|
| `Stream completed for` / `Stopping conversation stream` | → `done` |
| 4 秒内无新 `streamGenerateContent` | → `done`（响应完成）|
| 日志文件轮替（Antigravity 重启） | → `idle` |

**关键发现：** Antigravity 拒绝工具调用后，模型**完全不会**生成任何后续响应（没有 `streamGenerateContent`），唯一证据是 `approved=false` 那一行日志。早期版本曾尝试用固定超时（8s/20s）来兜底检测拒绝，但用户思考时间不固定，超时方案会在用户还在看确认框时误将状态变绿——因此改为**完全依赖明确日志信号**，不设超时，`waiting` 会一直保持直到收到上述任一信号。

**守护进程部署：**
```
~/.local/bin/agent-gemini-watcher
~/Library/LaunchAgents/com.agentbeacon.gemini-watcher.plist   # KeepAlive=true，崩溃自动重启
```

**手动兜底**（如果日志格式因 Antigravity 版本更新而变化）：
```bash
agent-beacon set antigravity running "启动任务"
agent-beacon set antigravity done "任务完成"
```

**已知限制：** 日志格式依赖 Antigravity 内部实现，未来版本升级可能改变日志文本，需要相应更新 `agent-gemini-watcher` 中的匹配模式。

---

## done 状态自动转 idle

点击菜单栏 → "done 自动转 idle" 可循环切换：
- 禁用（默认）
- 5 分钟后自动转 idle
- 10 分钟后
- 30 分钟后

`waiting` 状态**永远不自动消失**，必须手动重置。

---

## 开机自启

已安装四个 LaunchAgent：

| Label | 作用 | KeepAlive |
|-------|------|-----------|
| `com.agentbeacon.app` | 启动 AgentBeacon.app（菜单栏 + 浮窗） | false |
| `com.agentbeacon.gemini-watcher` | Antigravity 日志监听守护进程 | true（崩溃自动重启）|
| `com.agentbeacon.claude-watcher` | Claude Code 会话记录监听守护进程（补充 hooks 盲区） | true（崩溃自动重启）|
| `com.agentbeacon.codex-watcher` | Codex 会话记录监听守护进程（补充 hooks 盲区） | true（崩溃自动重启）|

日志：
- App: `/tmp/agent-beacon-stdout.log`、`/tmp/agent-beacon-stderr.log`
- AGY watcher: `/tmp/agent-gemini-watcher.log`
- Claude watcher: `/tmp/agent-claude-watcher.log`
- Codex watcher: `/tmp/agent-codex-watcher.log`

手动控制（以 gemini-watcher 为例，其余两个同理）：
```bash
launchctl load   ~/Library/LaunchAgents/com.agentbeacon.gemini-watcher.plist
launchctl unload ~/Library/LaunchAgents/com.agentbeacon.gemini-watcher.plist

# 重启某个服务（修改脚本后生效）
launchctl unload ~/Library/LaunchAgents/com.agentbeacon.gemini-watcher.plist
launchctl load   ~/Library/LaunchAgents/com.agentbeacon.gemini-watcher.plist
```

---

## 安全说明

- 所有数据**仅保存在本机** `~/.agent-beacon/`
- 状态文件不含：提示词、命令内容、环境变量、API Key、Token、Cookie
- 不上传任何数据
- 修改 `settings.json` 前创建带时间戳备份

---

## 启动 / 停止 / 卸载 / 恢复

### 启动 App
```bash
open /Applications/AgentBeacon.app
```

### 停止 App
```bash
killall AgentBeaconApp
```

### 卸载
```bash
bash Scripts/uninstall.sh
```
卸载脚本会：
- 停止 App
- 删除 `/Applications/AgentBeacon.app`
- 删除 `~/.local/bin/agent-beacon*`（或 `/usr/local/bin/`）
- 删除 LaunchAgent plist
- **不修改** `~/.agent-beacon/status/`（保留状态数据）
- **不修改** `~/.claude/settings.json`（保留 hooks）

### 恢复 Claude Code 配置
```bash
# 查看备份
ls ~/.claude/settings.json.agent-beacon-backup-*

# 恢复原始配置
cp ~/.claude/settings.json.agent-beacon-backup-YYYYMMDD-HHMMSS ~/.claude/settings.json
```

### 恢复 Codex 配置
```bash
ls ~/.codex/config.toml.agent-beacon-backup-*
cp ~/.codex/config.toml.agent-beacon-backup-YYYYMMDD-HHMMSS ~/.codex/config.toml
```

---

## 调试

```bash
# 查看当前状态
agent-beacon list

# 查看 App 日志
tail -f /tmp/agent-beacon-stderr.log

# 检查 App 是否运行
pgrep -l AgentBeaconApp

# 验证 Claude Code hooks（在 claude 会话中测试）
# 提交一个提示词后执行：
agent-beacon list  # 应该看到 claude → running

# 手动测试通知 hook
echo '{"message": "permission needed"}' | /Users/loutengda/.local/bin/agent-beacon-claude-notify
agent-beacon list  # claude 应该变为 waiting

# 手动测试 Codex notify
/Users/loutengda/.local/bin/agent-beacon-codex-notify turn-ended
agent-beacon list  # codex 应该变为 done
```

---

## 已知限制

1. **Codex hooks 首次信任**：交互终端（`codex`）首次运行时需在对话框中手动信任 hooks，之后自动生效
2. **Codex Desktop App**：`hooks.json` 和 `notify` 均在 `~/.codex/` 下，Desktop 应读取同一配置，但未单独实测确认
3. **Antigravity 日志依赖**：状态检测依赖对内部日志格式的逆向分析，Antigravity 版本升级可能导致匹配失效，需要时更新 `agent-gemini-watcher`
4. **Claude Code Desktop**：settings.json hooks 是否在 Desktop App 中生效未经实测验证（仅验证了 CLI）
5. **VS Code / JetBrains 内嵌终端**：读取同一 settings.json，hooks 应生效但未逐一验证
6. **应用签名**：App bundle 未签名，首次打开需在 Gatekeeper 中允许（`xattr -cr` 已处理）
7. **额度/用量监测**：当前版本不包含此功能（讨论过 Codex/Claude/AGY 各自的可行性，决定暂不实现）

---

## 构建要求

- macOS 13+
- Swift 5.8+（Xcode Command Line Tools，无需完整 Xcode）
- 无外部依赖
