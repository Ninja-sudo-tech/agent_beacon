# Agent Beacon

macOS 菜单栏应用，同时显示 Claude Code、Codex 和 Antigravity 的任务状态。  
全程静音，不显示 Dock 图标，不使用系统通知。

---

## 目录结构

```
agent_beacon/
├── Sources/
│   ├── Core/          # 共享状态模型和文件存储
│   ├── CLI/           # agent-beacon CLI 工具
│   └── App/           # AppKit MenuBar 应用
├── Tests/             # 独立测试套件 (50 项测试)
├── Resources/         # Info.plist、LaunchAgent.plist
├── Wrappers/          # Claude/Codex hook 脚本
└── Scripts/           # build、install、uninstall、setup-hooks
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

菜单栏图标显示三个 Agent 中**优先级最高**的状态：  
`error > waiting > running > done > idle`

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

已配置以下 hooks：

| 事件 | 触发条件 | 状态变化 |
|------|----------|----------|
| `UserPromptSubmit` | 用户提交提示词 | → `running` |
| `Stop` | 会话结束 | → `done` |
| `Notification` | 收到通知（检查关键词）| 可能 → `waiting` |

**等待状态局限：**  
Claude Code 没有专门的 `PermissionRequest` hook 事件。`Notification` hook 会检查消息中是否包含 "permission"、"approval"、"waiting" 等关键词来判断是否进入 `waiting` 状态，这是**近似实现**，非 100% 准确。

**IDE 集成状态：**  
- ✅ Claude Code CLI：hooks 通过 settings.json 生效
- ⚠️ JetBrains/VS Code 集成：读取同一 settings.json，hooks **应该**生效，但需实测验证
- ❓ Claude Code Desktop：是否执行 settings.json hooks 需实测（桌面版可能有独立配置）

---

## Codex 集成

**版本：** Codex CLI 0.142.2  
**集成方式：** `~/.codex/config.toml` `notify` 字段 + `agent-codex` 包装器

### notify hook（自动）
当 Codex 一轮对话结束时，会调用 `notify` 脚本并传入 `"turn-ended"` 参数：
```
notify → done
```
原始的 Codex Computer Use 客户端调用被保留（包装器先调用原始客户端）。

### agent-codex 包装器（CLI exec 模式）
对于 `codex exec` 命令，使用 `agent-codex` 替代可获得更精细的状态：
```bash
agent-codex "帮我重构这段代码"
agent-codex --interactive   # 启动 TUI 模式（手动状态）
```

事件检测：
- 会话开始 → `running`
- JSONL 中出现 `approval`、`waiting` 等关键词 → `waiting`（近似）
- 正常退出 → `done`
- 非零退出码 → `error`

**Codex Desktop 状态：**  
- ✅ `notify` hook 在 CLI 模式下生效（已通过配置文件确认）
- ❓ Codex Desktop App 是否读取同一 config.toml 的 `notify` 字段需实测
- 如果 Desktop App 不执行 notify hook，可手动使用 `agent-beacon set codex ...`

---

## Antigravity 集成

**版本：** Antigravity Desktop App（Electron）  
**自动集成：** ❌ 不可用

Antigravity 是一个 Electron 应用，没有：
- CLI 接口
- 官方 hooks / 事件 API
- 可编程访问的任务状态接口

可执行的二进制：`language_server`、`webm_encoder`（均非任务状态接口）

**可用方案：**
1. **手动通过 CLI 设置状态**（推荐）：
   ```bash
   agent-beacon set antigravity running "启动任务"
   # ... 完成后 ...
   agent-beacon set antigravity done "任务完成"
   ```
2. **通过菜单栏手动切换**：点击 Antigravity 项目下的"设为空闲"
3. **键盘快捷键**（可通过 Automator 或 KeyboardMaestro 绑定 agent-beacon 命令）

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

已安装 LaunchAgent：
```
~/Library/LaunchAgents/com.agentbeacon.app.plist
```

- 登录后自动启动 `/Applications/AgentBeacon.app`
- 日志：`/tmp/agent-beacon-stdout.log`、`/tmp/agent-beacon-stderr.log`

手动控制：
```bash
launchctl load   ~/Library/LaunchAgents/com.agentbeacon.app.plist
launchctl unload ~/Library/LaunchAgents/com.agentbeacon.app.plist
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

1. **Claude Code PermissionRequest**：没有专用 hook，通过 `Notification` 事件关键词近似检测
2. **Codex 交互模式**：TUI 模式下无法自动检测状态，需手动设置
3. **Codex Desktop App**：未验证是否执行 config.toml notify hook（CLI 已验证）
4. **Antigravity**：无任何自动集成接口，完全手动
5. **Claude Code Desktop**：settings.json hooks 是否在 Desktop App 中生效未经实测验证
6. **VS Code / JetBrains**：读取同一 settings.json，hooks 应生效但未验证
7. **应用签名**：App bundle 未签名，首次打开需在 Gatekeeper 中允许（`xattr -cr` 已处理）

---

## 构建要求

- macOS 13+
- Swift 5.8+（Xcode Command Line Tools，无需完整 Xcode）
- 无外部依赖
