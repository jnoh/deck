---
status: done
priority: p0
---

# Spec: Session Packages

## Goal

Replace flat TOML blueprints with directory packages that bundle config, scripts, and integration logic together. Packages are self-contained, shareable, and extensible without changing the app.

## Background

Currently, session blueprints are single `.toml` files in `~/.config/deck/sessions/`. Integration logic (like Claude Code hook injection) is hardcoded in Swift. This doesn't scale — every new program integration requires app changes.

Directory packages solve this by letting the package define its own startup, teardown, and status reporting logic via scripts.

## Design

### Package Structure

A session package is a directory with a `.deck` extension:

```
~/.config/deck/sessions/claude-code.deck/
├── session.toml          # Required — config (same schema, minus startup.steps)
├── start.sh              # Required — startup script (replaces startup.steps)
├── stop.sh               # Optional — teardown script (replaces teardown.steps)
├── health.sh             # Optional — health check (replaces health.command)
└── ...                   # Any supporting files the scripts need
```

Plain `.toml` files continue to work for simple sessions. Deck auto-detects: directory with `.deck` extension → package, `.toml` file → flat blueprint.

### session.toml (simplified)

Inside a package, the TOML no longer needs `startup.steps`, `teardown.steps`, or `health.command` — those are scripts:

```toml
[session]
name = "claude-code"
icon = "🤖"
description = "Claude Code agent"
type = "local"

[startup]
working_dir = "~"
```

### start.sh

The startup script is the entry point. It runs inside the session's PTY with the `deck` function already available. It can do anything — install dependencies, configure hooks, launch the program:

```bash
#!/bin/bash
# start.sh for claude-code

deck status --state starting --desc "Launching Claude Code"

# Build the Claude --settings JSON for status hooks
HOOKS=$(cat <<'HOOKS_EOF'
{"hooks":{
  "Notification":[{"hooks":[{"type":"command","command":"deck status --state needs-input --desc 'Waiting for input'"}]}],
  "Stop":[{"hooks":[{"type":"command","command":"deck status --state idle --desc Ready"}]}],
  "PostToolUse":[{"hooks":[{"type":"command","command":"deck status --state working --desc Working"}]}]
}}
HOOKS_EOF
)

exec claude --settings "$HOOKS"
```

### stop.sh (optional)

Runs before the session is killed:

```bash
#!/bin/bash
deck status --state stopping --desc "Shutting down"
# Any cleanup
```

### health.sh (optional)

Exit 0 = healthy, non-zero = degraded:

```bash
#!/bin/bash
pgrep -f claude > /dev/null
```

### Script Environment

All scripts run with:
- `deck` function available (sourced from env script)
- `DECK_SESSION_ID` set
- `DECK_SESSION_NAME` set
- `DECK_PACKAGE_DIR` set to the package directory path
- Working directory set to `startup.working_dir`

### Loading

`ConfigLoader` discovers packages by scanning for both `.toml` files and `.deck` directories:
- `.toml` → load as flat blueprint (existing behavior)
- `.deck/` → read `session.toml` inside, set `start.sh` as the command

### Example Packages

**claude-code.deck** — Claude Code with status hooks
**dev-server.deck** — Node/Python dev server with port detection
**ssh-workspace.deck** — Remote Coder workspace with provisioning

## Acceptance Criteria

- [ ] `ConfigLoader` discovers `.deck` directories alongside `.toml` files
- [ ] Package's `session.toml` is parsed for config
- [ ] `start.sh` is executed as the session command (not `startup.steps`)
- [ ] `stop.sh` runs on session teardown if present
- [ ] `health.sh` is used for health checks if present
- [ ] `DECK_PACKAGE_DIR` env var set to the package path
- [ ] `deck` function available in all package scripts
- [ ] Flat `.toml` files still work (backward compatible)
- [ ] `program` field and `injectClaudeHooks` removed from Swift code
- [ ] Ship a `claude-code.deck` example package
- [ ] Visual verification: create session from package, verify terminal + status

## Out of Scope

- Package registry / marketplace
- Package versioning
- Remote package installation
- Package validation/linting

## Approach

1. Update `ConfigLoader.loadAll()` to scan for `.deck` directories
2. Parse `session.toml` inside packages, store package dir path on `SessionConfig`
3. Update `TerminalSessionView` startup: if package has `start.sh`, use it as command instead of composing from `startup.steps`
4. Set `DECK_PACKAGE_DIR` env var
5. Remove `program` field and `injectClaudeHooks` from Swift
6. Create `claude-code.deck` package in `~/.config/deck/sessions/`

## Dependencies

- Spec 01 (Config Parsing) — `ConfigLoader` changes
- Spec 14 (Status System) — `deck` function in scripts
