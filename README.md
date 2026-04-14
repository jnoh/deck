# Deck

A native macOS app that orchestrates long-running CLI programs. You define sessions as packages, and Deck manages their lifecycle — starting, stopping, and switching between them through a sidebar with GPU-rendered terminal views.

Built for running multiple AI coding agents side by side.

## Install

Requires macOS 14+ and Xcode.

```bash
git clone https://github.com/yourname/deck.git
cd deck
./scripts/setup.sh      # downloads GhosttyKit (terminal renderer)
swift build
./scripts/bundle.sh     # wraps into .app bundle
open .build/Deck.app
```

## How it works

Sessions are defined as `.deck` packages in `~/.deck/apps/`. Each package is a directory containing a TOML config and a startup script.

```
~/.deck/apps/
├── claude-code.deck/
│   ├── session.toml
│   ├── start.sh
│   └── hooks/
└── hello-world.deck/
    ├── session.toml
    └── start.sh
```

Click **+** in the sidebar to create a session from a package. Pick a working directory, name it, and it launches.

## Create a session package

### Minimal example

```bash
mkdir -p ~/.deck/apps/my-shell.deck
```

**~/.deck/apps/my-shell.deck/session.toml**
```toml
[session]
name = "my-shell"
type = "local"
icon = "🐚"
description = "A simple shell"

[startup]
working_dir = "~"
```

**~/.deck/apps/my-shell.deck/start.sh**
```bash
#!/bin/bash
echo "Ready to go."
exec "${SHELL:-/bin/zsh}" -l
```

```bash
chmod +x ~/.deck/apps/my-shell.deck/start.sh
```

Restart Deck. Your new package appears in the **+** menu.

### With status reporting

Deck injects a `deck` CLI into every session's PATH. Programs can report their state back to the sidebar:

```bash
deck status --state working --desc "Building project"
deck status --state idle --desc "Done"
deck status --state needs-input --desc "Waiting for input"  # triggers macOS notification
deck title "My Project"
deck notify --text "Tests passed" --level success
deck exit                                                    # closes the session
```

### Claude Code integration

The included `claude-code.deck` package launches Claude Code with hooks that automatically report status to the sidebar — working, waiting for input, idle. The session title is generated from your first prompt.

**~/.deck/apps/claude-code.deck/start.sh** injects Claude Code hooks via `--settings`:

```bash
#!/bin/bash
deck status --state starting --desc "Launching Claude Code"

HOOK_DIR="${DECK_PACKAGE_DIR}/hooks"

HOOKS=$(cat <<EOF
{"hooks":{
  "UserPromptSubmit":[{"hooks":[{"type":"command","command":"$HOOK_DIR/on-prompt.sh"}]}],
  "PostToolUse":[{"hooks":[{"type":"command","command":"deck status --state working --desc Working"}]}],
  "Stop":[{"hooks":[{"type":"command","command":"deck status --state needs-input --desc 'Your turn'"}]}]
}}
EOF
)

claude --settings "$HOOKS"
deck exit
```

No PATH shims, no plugins — just `--settings` to inject hooks for a single session.

## Architecture

- **SwiftUI** app shell with sidebar and terminal detail view
- **libghostty** for GPU-accelerated terminal rendering (Metal)
- **TOMLKit** for config parsing
- **Session packages** (`.deck` directories) define lifecycle via scripts
- **`deck` CLI** on PATH for status reporting (writes to a polled status file)
- Sidebar updates dynamically from status — custom states, descriptions, notification badges
- macOS notifications when a session needs your attention

## Session package reference

### session.toml

```toml
[session]
name = "my-app"          # required — unique identifier
type = "local"            # required — "local" or "remote"
icon = "🚀"              # optional — emoji for sidebar
description = "My app"   # optional — subtitle in sidebar

[startup]
working_dir = "~/code"   # optional — default working directory

[host]                    # required for type = "remote"
ssh = "ssh user@host"
provision = "..."         # optional — run before connecting
deprovision = "..."       # optional — run after disconnecting
ready_check = "..."       # optional — poll until ready
ready_timeout_seconds = 120

[health]
command = "true"          # optional — exit 0 = healthy
interval_seconds = 10
```

### Scripts

| File | Purpose |
|---|---|
| `start.sh` | Required. Entry point. When it exits, the session closes. |
| `stop.sh` | Optional. Runs before the session is killed. |
| `health.sh` | Optional. Exit 0 = healthy, non-zero = degraded. |
| `hooks/` | Optional. Helper scripts called from start.sh. |

### Environment

Every session has these available:

| Variable | Description |
|---|---|
| `DECK_SESSION_ID` | Unique session instance ID |
| `DECK_SESSION_NAME` | Display name |
| `DECK_PACKAGE_DIR` | Path to the .deck package directory |
| `deck` | CLI on PATH for status reporting |

## Development

```bash
swift build                          # build
swift test                           # run tests (74 tests)
swift build && ./scripts/bundle.sh   # build .app bundle
open .build/Deck.app                 # run
```

## License

MIT
