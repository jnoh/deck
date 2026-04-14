# Deck

A native macOS app that orchestrates long-running CLI programs. You define sessions declaratively, and Deck manages their lifecycle — starting, stopping, health-checking, and switching between them through a unified sidebar interface.

## Architecture

### Session Types

**Local sessions.** Deck spawns a PTY directly. No tmux, no multiplexer. The app owns the process. Feels like a native terminal. If the app quits, local sessions die.

**Remote sessions.** Deck SSHes into a remote host and creates an invisible tmux session there. tmux exists solely to keep the remote process alive across SSH drops. The user never interacts with tmux directly. If SSH drops, Deck reconnects and reattaches transparently.

### App Structure

```
SwiftUI App
├── Sidebar (session list, grouped by state)
├── Content Area (terminal view for selected session)
├── Session Manager (lifecycle orchestration)
├── Config Watcher (FSEvents on config directory)
└── Health Monitor (background polling)
```

The terminal view uses SwiftTerm (or libghostty if terminal rendering quality demands it). One SwiftTerm instance per active session. Clicking a session in the sidebar swaps which instance is visible.

## Session Definitions

TOML files in `~/.config/deck/sessions/`. The app watches this directory and live-reloads on changes.

### Local Session

```toml
[session]
name = "claude-code"
type = "local"
icon = "🤖"
description = "Claude Code on local project"

[startup]
working_dir = "~/projects/myapp"
steps = [
  "claude",
]

[teardown]
steps = []

[health]
command = "pgrep -f claude"
interval_seconds = 10
```

### Remote Session

```toml
[session]
name = "remote-claude"
type = "remote"
icon = "🌐"
description = "Claude Code on Coder workspace"

[host]
provision = "coder create my-workspace --template=ubuntu --yes"
ssh = "coder ssh my-workspace"
deprovision = "coder stop my-workspace --yes"
ready_check = "coder ssh my-workspace -- echo ok"
ready_timeout_seconds = 300

[startup]
working_dir = "/workspace/myapp"
steps = [
  "claude",
]

[teardown]
steps = []

[health]
command = "coder list --output=json | jq -e '.[] | select(.name==\"my-workspace\") | .latest_build.status == \"running\"'"
interval_seconds = 30
```

### Schema Reference

| Field | Required | Default | Description |
|---|---|---|---|
| `session.name` | yes | — | Unique identifier. Used as tmux session name for remote. |
| `session.type` | yes | — | `local` or `remote` |
| `session.icon` | no | `▸` | Emoji shown in sidebar |
| `session.description` | no | `""` | Subtitle in sidebar |
| `host.provision` | no | — | Local command to provision remote host before SSH |
| `host.ssh` | no | — | SSH command (e.g. `ssh user@host` or `coder ssh ws`) |
| `host.deprovision` | no | — | Local command to tear down remote host after session ends |
| `host.ready_check` | no | — | Local command polled until remote host is ready (exit 0) |
| `host.ready_timeout_seconds` | no | `120` | Timeout for ready_check polling |
| `startup.working_dir` | no | `~` | Directory to cd into before running steps |
| `startup.steps` | no | `[]` | Ordered shell commands. Composed into a single script. Last command is the long-running process. |
| `teardown.steps` | no | `[]` | Commands run before killing the session |
| `health.command` | no | `"true"` | Exit 0 = healthy, non-zero = degraded. Runs locally for both session types. |
| `health.interval_seconds` | no | `10` | Polling interval |

## Lifecycle

### States

```
stopped → provisioning → starting → running ⇄ degraded → stopping → deprovisioning → stopped
```

Local sessions skip `provisioning` and `deprovisioning`.

### Local Startup

1. Compose `startup.steps` into a single shell script.
2. Spawn PTY: `bash -l -c 'cd <working_dir> && bash /tmp/deck-<name>.sh'`
3. Create SwiftTerm instance attached to the PTY.
4. Transition to `running`.
5. Begin health check polling.

### Remote Startup

1. Run `host.provision` locally (if present).
2. Poll `host.ready_check` until exit 0 or timeout. State: `provisioning`.
3. Pipe startup script to remote host over SSH, write to `/tmp/deck-<name>.sh`.
4. Create remote tmux session: `<host.ssh> -- tmux new-session -d -s deck-<name> 'cd <working_dir> && bash /tmp/deck-<name>.sh'`
5. Create SwiftTerm instance running: `<host.ssh> -- tmux attach -t deck-<name>`
6. Transition to `running`.
7. Begin health check polling.

### Teardown (both types)

1. Transition to `stopping`.
2. For local: send teardown commands into the PTY, then terminate the process.
3. For remote: send teardown commands into remote tmux via SSH, kill remote tmux session.
4. For remote with deprovision: run `host.deprovision` locally. State: `deprovisioning`.
5. Transition to `stopped`.
6. Destroy the SwiftTerm instance.

### Reconnection (remote only)

1. Monitor the SSH PTY process.
2. On unexpected exit, check if health check still passes.
3. If healthy: remote tmux session is still alive. Auto-reconnect by re-running the SSH attach command. Swap in new SwiftTerm instance.
4. If unhealthy: transition to `degraded`. Show reconnect button in sidebar.

## UI

### Sidebar

- Grouped sections: Running, Degraded, Starting, Stopped.
- Each row: icon, name, status dot (green/yellow/pulsing/gray), description.
- Right-click context menu: Start, Stop, Restart, Edit Config, Show in Finder.
- "+" button at bottom to create new session (scaffolds a TOML file and opens in editor).
- Sessions reorder within groups by name.

### Terminal Content Area

- Full terminal view of the selected session.
- When no session is selected or active: empty state with instructions.
- When session is starting: show terminal output of the startup process.
- Standard terminal interactions: scrollback, selection, copy/paste.

### Status Indicators

- Green: `running` — process alive, health check passing
- Yellow: `degraded` — process alive, health check failing
- Gray: `stopped` — no process
- Pulsing animation for `provisioning`, `starting`, `stopping`, `deprovisioning`

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+1..9` | Jump to session by position |
| `Cmd+[` / `Cmd+]` | Previous / next session |
| `Cmd+N` | New session definition |
| `Cmd+W` | Stop selected session |
| `Cmd+R` | Restart selected session |
| Global hotkey (configurable) | Bring Deck to front |

### Menu Bar

- Persistent menu bar icon.
- Dropdown shows session list with status dots.
- Click a session to bring Deck to front with that session selected.
- Quick actions: Start All, Stop All.

### URL Scheme

`deck://start/<session-name>` — start a session (for Raycast, Shortcuts, etc.)
`deck://stop/<session-name>` — stop a session
`deck://open/<session-name>` — bring app to front with session selected

## Tech Stack

- **SwiftUI** — app shell, sidebar, settings, menu bar
- **SwiftTerm** — embedded terminal views (evaluate libghostty if rendering quality is insufficient)
- **Foundation.Process** — PTY spawning for local sessions, SSH commands for remote
- **FSEvents / DispatchSource** — watch config directory for changes
- **TOML parsing** — use a Swift TOML library (e.g. TOMLKit)
- **Combine / async-await** — health check polling, state management

## Build and Distribution

- Xcode project, Swift Package Manager for dependencies.
- Target macOS 14+ (Sonoma).
- Distribute via direct download initially. Mac App Store later if sandboxing is feasible (PTY spawning may conflict).

## Future Considerations (not in v1)

- **Session templates with parameters** — e.g. a generic "remote-claude" template where workspace name is a variable passed at launch time.
- **Multi-pane sessions** — a single session definition that creates a split view (e.g. dev server + log tail).
- **Session groups / folders** — organize sessions into categories in the sidebar.
- **Shared config** — team-level session definitions synced via git, layered on top of local config.
- **Notifications** — alert when a session degrades or startup completes.
