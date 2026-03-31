# Multi Coding Agents

English version: [README.md](./README.md)

一个面向 `Claude Code` 和 `Codex` 的实用型多代理方案。

这个仓库提供：

- 一组职责清晰的 coding agents
- 一个以 `coordinator` 为核心的路由模型
- 一套同时支持 Claude Code 和 Codex 的安装脚本

默认路径保持简单，专业角色按需进入。

## 为什么做这个

这套 agent pack 处在过轻的单代理方案和过重的高编排系统之间。

- `implementer` 负责实际实现
- `code-simplifier` 负责在不改行为的前提下清理最近改动
- `reviewer` 负责独立、偏风险导向的复查
- `researcher` 只在缺少上下文、证据或最新资料时介入
- `architect` 只在设计确实复杂时介入
- `coordinator` 负责决定该走哪条路径，并对最终结果负责

默认路径：

```text
coordinator
  -> implementer
  -> code-simplifier
  -> reviewer
```

## 仓库包含什么

### 可安装 Agent

- [`agents/coordinator.md`](./agents/coordinator.md)：负责路由和协调
- [`agents/implementer.md`](./agents/implementer.md)：主执行 agent
- [`agents/code-simplifier.md`](./agents/code-simplifier.md)：轻量清理 agent
- [`agents/reviewer.md`](./agents/reviewer.md)：风险导向 reviewer
- [`agents/researcher.md`](./agents/researcher.md)：上下文与证据收集
- [`agents/architect.md`](./agents/architect.md)：仅负责设计判断

### 安装器与 Claude Plugin 元数据

- [`install-agents.sh`](./install-agents.sh)：安装到 Claude Code 和/或 Codex
- [`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json)：Claude Code plugin manifest
- [`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json)：Claude Code marketplace manifest

## 设计原则

- `agents/` 是可安装角色的唯一真源。
- 默认路径必须简单、稳定、容易解释。
- `architect` 是条件角色，不是必选角色。
- `code-simplifier` 应长期存在，但职责要非常窄。
- 中高风险改动必须有独立 review 压力。
- 平台支持范围以官方可确认能力为准，不做“猜测式支持”。

## 平台支持

### Claude Code

`Claude Code` 只支持 plugin 安装路线。

支持的 scope：

- `user`
- `project`
- `local`

### Codex

`Codex` 安装由 `agents/` 生成：

- 把 `agents/` 下的 Markdown agent 转成 `.codex/agents/*.toml`
- 在安装时把受管路由规则写入目标 `AGENTS.md`

支持的 scope：

- `user`
- `project`

## 安装

### 依赖

- `bash`
- `node`
- Claude 安装时需要 `Claude Code` CLI
- Claude 安装状态检测需要 `jq`
- 远程 GitHub 安装需要 `curl` 和 `tar`

### 交互式安装（推荐）

远程安装：

```bash
curl -fsSL https://raw.githubusercontent.com/JoJoJotarou/cc-multi-agent/master/install-agents.sh | \
  bash -s --
```

本地仓库：

```bash
./install-agents.sh
```

### 带参数示例

在目标项目目录外安装到某个项目：

```bash
./install-agents.sh --target all --scope project --project-dir /path/to/target-project
```

只安装到 Codex 用户级：

```bash
./install-agents.sh --target codex --scope user
```

把 `coordinator` 设为目标项目的 Claude 默认 agent：

```bash
./install-agents.sh --target claude --scope project --project-dir /path/to/target-project --activate-coordinator yes
```

远程安装也支持同样的参数，把 `./install-agents.sh` 替换成上面的远程命令即可。

其他情况直接改参数：

- `--target` 支持 `claude`、`codex`、`all`
- `--scope` 支持 `user`、`project`、`local`，其中 `local` 只用于 Claude
- `--project-dir` 用于在目标项目目录外执行安装
- `--activate-coordinator yes` 会把 `coordinator` 写成 Claude 默认 agent
- `--dry-run` 只预览，不写文件

## 安装器实际会做什么

### 对 Claude Code

Claude 安装会：

- 准备一个持久化的本地 plugin source cache
- 调用本地 `claude plugin validate`
- 调用本地 `claude plugin marketplace add/update`
- 调用本地 `claude plugin install --scope ...`

使用 `--activate-coordinator yes` 时，安装器还会写入这份 Claude plugin `settings.json`：

```json
{
  "agent": "jojojotarou-cc-multi-agent:coordinator"
}
```

### 对 Codex

Codex 安装会：

- 把 `agents/` 下的每个 Markdown agent 转成 Codex `.toml`
- 写入 `~/.codex/agents/` 或 `<project>/.codex/agents/`
- 更新 `~/.codex/AGENTS.md` 或 `<project>/AGENTS.md`
- 只写入受管块，不覆盖无关内容

## 推荐使用方式

默认路径：

```text
implementer -> code-simplifier -> reviewer
```

在这些情况下加上 `researcher`：

- 代码路径还没搞清楚
- Bug 根因还不明确
- 需要依赖最新外部信息

在这些情况下加上 `architect`：

- 改动跨模块或跨服务
- 牵涉 API、Schema、契约设计
- 需要考虑迁移、发布、兼容性
- 存在多个合理方案且取舍真实存在

需要显式路由这些判断时，把入口交给 `coordinator`。

## 目录结构

```text
.
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── agents/
│   ├── architect.md
│   ├── code-simplifier.md
│   ├── coordinator.md
│   ├── implementer.md
│   ├── researcher.md
│   └── reviewer.md
├── README.md
├── README.zh-CN.md
└── install-agents.sh
```

## 备注

- `agents/` 是可安装角色的唯一真源。
- Claude 侧只支持 plugin 路线。
- Codex 项目级安装会更新目标项目的 `AGENTS.md`。
- Codex 用户级安装会更新 `~/.codex/AGENTS.md`。

## License

MIT
