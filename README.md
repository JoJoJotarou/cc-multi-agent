# Multi Coding Agents

简体中文说明见：[README.zh-CN.md](./README.zh-CN.md)

A practical multi-agent pack for `Claude Code` and `Codex`.

This repo ships:

- a focused set of coding agents
- a coordinator-led routing model
- one installer for Claude Code and Codex

The default path stays small. Specialist roles stay conditional.

## Why This Exists

This pack sits between underpowered single-agent setups and over-orchestrated agent systems.

- `implementer` ships the change
- `code-simplifier` cleans up touched code without changing behavior
- `reviewer` does an independent risk-focused pass
- `frontend-reviewer` evaluates rendered page quality, style fidelity, accessibility, responsiveness, and performance
- `researcher` is added when context or evidence is missing
- `architect` is added only when design choices are genuinely non-trivial
- `coordinator` selects the path and owns the final outcome

Default route:

```text
coordinator
  -> implementer
  -> code-simplifier
  -> reviewer
```

## What’s Included

### Installable Agents

- [`agents/coordinator.md`](./agents/coordinator.md): routes work across specialists
- [`agents/implementer.md`](./agents/implementer.md): main execution agent
- [`agents/code-simplifier.md`](./agents/code-simplifier.md): lightweight cleanup pass
- [`agents/reviewer.md`](./agents/reviewer.md): independent risk-focused reviewer
- [`agents/frontend-reviewer.md`](./agents/frontend-reviewer.md): rendered UI and frontend page-quality reviewer
- [`agents/researcher.md`](./agents/researcher.md): evidence and context gathering
- [`agents/architect.md`](./agents/architect.md): design-only agent for non-trivial decisions

### Installer and Claude Plugin Metadata

- [`install-agents.sh`](./install-agents.sh): installs to Claude Code and/or Codex
- [`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json): Claude Code plugin manifest
- [`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json): Claude Code marketplace manifest

## Design Principles

- Keep `agents/` as the source of truth for installable agent roles.
- Keep the default path simple and predictable.
- Make `architect` conditional, not mandatory.
- Treat `code-simplifier` as always-available and intentionally narrow.
- Require review pressure for medium- and high-risk changes.
- Support both user-level and project-level installation where the platform allows it.
- Prefer explicit scope support over undocumented hacks.

## Platform Support

### Claude Code

`Claude Code` support is plugin-only.

Supported scopes:

- `user`
- `project`
- `local`

Claude standalone agents are out of scope for this repo.

### Codex

`Codex` support is generated from `agents/`:

- writing subagent files into `.codex/agents/`
- updating the target `AGENTS.md` with a managed routing block during installation

Supported scopes:

- `user`
- `project`

`Codex local` is not supported by this installer. Public Codex subagent docs currently document user-level and project-level locations only.

## Installation

### Requirements

- `bash`
- `node`
- `Claude Code` CLI for Claude installs
- `jq` for Claude install state detection
- `curl` and `tar` for remote GitHub source installs

### Recommended Interactive Install

Remote install:

```bash
curl -fsSL https://raw.githubusercontent.com/JoJoJotarou/cc-multi-agent/master/install-agents.sh | \
  bash -s --
```

Remote installs use `JoJoJotarou/cc-multi-agent` on `master`.

For Claude Code, remote installs declare the marketplace as a GitHub source.

The guided installer covers target, scope, project directory, and Claude coordinator activation.

Local checkout:

```bash
./install-agents.sh
```

### Parameterized Examples

Install into a target project from outside that project:

```bash
./install-agents.sh --target all --scope project --project-dir /path/to/target-project
```

Install only for Codex at user level:

```bash
./install-agents.sh --target codex --scope user
```

Activate `coordinator` as the default Claude agent for a target project:

```bash
./install-agents.sh --target claude --scope project --project-dir /path/to/target-project --activate-coordinator yes
```

Use the same flags with remote installs by replacing `./install-agents.sh` with the remote command above.

Change parameters as needed:

- `--target` supports `claude`, `codex`, and `all`
- `--scope` supports `user`, `project`, and `local` (`local` is Claude-only)
- `--project-dir` selects the target project when you are outside that directory
- `--activate-coordinator yes` writes the target Claude `agent` setting
- `--dry-run` previews the install without writing files

## What the Installer Actually Does

### For Claude Code

Claude installation:

- local-checkout installs prepare a persistent directory source cache
- remote installs declare the marketplace as `github:JoJoJotarou/cc-multi-agent`
- local directory installs call `claude plugin validate`
- all Claude installs call `claude plugin marketplace add/update`
- calls the local `claude plugin install --scope ...` command

With `--activate-coordinator yes`, the installer also writes this target Claude settings entry:

```json
{
  "agent": "jojojotarou-cc-multi-agent:coordinator"
}
```

### For Codex

Codex installation:

- converts each Markdown agent in `agents/` into a Codex `.toml` subagent
- writes them into either `~/.codex/agents/` or `<project>/.codex/agents/`
- updates either `~/.codex/AGENTS.md` or `<project>/AGENTS.md`
- injects a managed routing policy block without overwriting unrelated content

## Suggested Workflow

Baseline path:

```text
implementer -> code-simplifier -> reviewer
```

Add `researcher` when:

- the codebase context is unclear
- the bug is not yet understood
- up-to-date external information matters

Add `frontend-reviewer` when:

- the task changes visible UI or page behavior
- you need evidence-based feedback on whether a page looks good enough to ship
- accessibility, responsiveness, or performance should be checked on the rendered page
- local style guidance or design tokens should be enforced against runtime output

Add `architect` when:

- the change spans modules or services
- API or schema decisions are involved
- migration, rollout, or compatibility matters
- there are multiple reasonable designs with real trade-offs

Use `coordinator` as the entrypoint when you want routing handled explicitly.

## Repository Structure

```text
.
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── agents/
│   ├── architect.md
│   ├── code-simplifier.md
│   ├── coordinator.md
│   ├── frontend-reviewer.md
│   ├── implementer.md
│   ├── researcher.md
│   └── reviewer.md
├── README.md
├── README.zh-CN.md
└── install-agents.sh
```

## Notes

- `agents/` is the canonical source for installable roles.
- Claude support is plugin-based only.
- `frontend-reviewer` expects browser tooling to exist in the host session. For Claude plugin installs, configure Chrome/Playwright MCP outside the plugin because plugin subagents do not ship `mcpServers`.
- Codex project installs update the target project's `AGENTS.md`.
- Codex user installs update `~/.codex/AGENTS.md`.
- If a platform capability is not clearly documented, this repo prefers not to fake support for it.

## License

Add your preferred license here.
