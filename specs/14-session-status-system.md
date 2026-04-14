---
status: done
priority: p0
---

# Spec: Session Status System

## Goal

Enable running programs to report dynamic status (state, description, progress, notifications) back to Deck's sidebar, using a transport that works identically for local and remote sessions.

## Background

Deck currently shows static status: running/stopped/degraded based on process lifecycle and health checks. For orchestrating AI agents like Claude Code, users need to see what the agent is actually doing — working, waiting for input, running tests, etc.

cmux solves this with a CLI + Unix socket + PATH shim approach. Deck can do it more cleanly using Claude Code's native `--settings` flag to inject hooks at launch, with a minimal `deck` CLI that abstracts the transport.

## Design

### Transport Layer

**File-based: the `deck` function writes JSON to a status file that Deck polls.**

Deck creates a per-session env script at `/tmp/deck-env-<session-id>.sh` containing a `deck()` shell function. The function writes JSON to `/tmp/deck-<session-id>.status`. Deck polls this file every 500ms, reads the JSON, applies the status update, and deletes the file.

```bash
# Auto-generated in /tmp/deck-env-<session-id>.sh
deck() { /bin/echo "$1" > '/tmp/deck-<session-id>.status'; }
export DECK_SESSION_ID='<session-id>'
```

Usage from hooks or scripts:
```bash
deck '{"type":"status","state":"working","desc":"Editing main.py"}'
```

The env script is sourced automatically by the session's startup wrapper script. Programs running inside the session can call `deck` without any setup.

Note: OSC-based transport was attempted but libghostty's `GHOSTTY_ACTION_SET_TITLE` callback does not fire for embedded surfaces using `GHOSTTY_SURFACE_CONTEXT_SPLIT`. File-based polling is simple and reliable for local sessions. For remote sessions, the `deck` function can be adapted to write to a file on the remote host, polled via SSH.

### Environment Variables

Deck sets these in the PTY environment for every session:

| Variable | Value | Purpose |
|---|---|---|
| `DECK_SESSION_ID` | Unique session instance ID | Identifies which session is reporting |
| `DECK_SESSION_NAME` | Display name | For logging/debugging |

### Status Protocol

The `deck` CLI exposes these commands:

```bash
deck status --state <state> [--desc "description"] [--icon "emoji"]
deck notify --text "message" [--level info|warning|error]
deck progress --value 0.0-1.0 [--label "description"]
deck log --level info|success|warning|error --text "message"
deck clear
```

All commands serialize to JSON and send via the active transport:

```json
{"type":"status","state":"working","desc":"Editing main.py","icon":"⚡"}
{"type":"notify","text":"Need your input","level":"warning"}
{"type":"progress","value":0.7,"label":"Running tests"}
{"type":"log","level":"success","text":"All tests passed"}
{"type":"clear"}
```

### Sidebar Rendering

The sidebar session row expands to show dynamic metadata below the session name:

```
 🤖 claude-code              🟢
    Working — Editing main.py
    ████████░░ 80% tests
```

Components:
- **State** — custom states beyond running/stopped (working, idle, needs-input, error)
- **Description** — short text describing current activity
- **Progress bar** — optional, 0.0–1.0 with label
- **Notification badge** — dot/count indicator when session needs attention

Custom states map to visual indicators:
- `working` → pulsing green dot
- `idle` → solid green dot
- `needs-input` → yellow dot + notification badge
- `error` → red dot
- Any other string → gray dot with text

### Claude Code Integration

When a blueprint has `program = "claude"`, Deck auto-constructs the launch command with `--settings` to inject hooks:

**Blueprint TOML:**
```toml
[session]
name = "claude-code"
program = "claude"
icon = "🤖"

[startup]
working_dir = "~/projects/app"
steps = ["claude"]
```

**What Deck actually runs:**
```bash
deck() { ... }  # shell function injected into environment
export DECK_SESSION_ID=xxx DECK_SOCKET=/tmp/deck-xxx.sock
claude --settings '{"hooks":{...}}' 
```

**Injected hooks:**

| Event | Status update |
|---|---|
| `SessionStart` | `deck status --state connected --desc "Session started"` |
| `PostToolUse` | `deck status --state working --desc "Using $CLAUDE_TOOL_NAME"` |
| `Stop` | `deck status --state idle --desc "Ready"` |
| `Notification` | `deck status --state needs-input --desc "Waiting for input"` |
| `SubagentStart` | `deck status --state working --desc "Subagent running"` |

The user never configures this. Deck generates it from `program = "claude"`.

### Extensibility to Other Programs

The `program` field in the blueprint tells Deck which hook template to use:

```toml
program = "claude"    # Claude Code hooks via --settings
program = "aider"     # Future: aider-specific status
program = "codex"     # Future: codex-specific status
```

Programs without a known template can still use the `deck` CLI manually in their startup steps:

```toml
[startup]
steps = [
  "deck status --state starting --desc 'Booting dev server'",
  "npm run dev",
]
```

### Remote Session Handling

No difference from local. The `deck` shell function emits OSC sequences into the PTY, which travel through SSH transparently. Deck injects the function into the startup environment for both local and remote sessions identically.

## Acceptance Criteria

- [x] `deck` shell function injected into PTY environment for all sessions
- [x] `DECK_SESSION_ID` env var set for all sessions
- [x] Status file polling (`/tmp/deck-<session-id>.status`) reads JSON updates
- [x] Sidebar row renders dynamic description below session name
- [x] Sidebar row renders custom state indicator (working/idle/needs-input/error)
- [x] Notification badge on session row when `notify` received
- [x] `program` field added to blueprint TOML schema
- [ ] `program = "claude"` auto-injects `--settings` with hooks (hook template built, needs e2e test with Claude)
- [x] Programs not aware of Deck still work normally (no-op if `deck` not called)
- [x] Visual verification: status update changes sidebar description and dot color

## Out of Scope

- Progress bar rendering (future enhancement)
- Log panel UI (future enhancement)
- Shims for programs other than Claude Code (future, per-program)
- Bidirectional communication (Deck → program)

## Approach

### Phase 1: Transport + CLI

1. Add `deck` shell function to PTY environment injection in `TerminalSessionView`
2. Intercept `GHOSTTY_ACTION_SET_TITLE` in `GhosttyService.handleAction` — parse `deck:` prefixed titles
3. Define `SessionStatus` model: state, description, icon, notification count
4. Route parsed status updates to the correct `Session` via `DECK_SESSION_ID`

### Phase 2: Sidebar Rendering

1. Add `status` property to `Session` (observable)
2. Update `SessionRowView` to render description and custom state dot
3. Add notification badge indicator

### Phase 3: Claude Code Integration

1. Add `program` field to `SessionConfig` TOML schema
2. Build hook template for `program = "claude"`
3. Auto-construct `--settings` JSON and prepend to startup command
4. Test end-to-end with Claude Code

## Dependencies

- Spec 01 (Config Parsing) — new `program` field in blueprint TOML
- Spec 07/13 (Terminal View) — OSC title interception via ghostty callback

## References

- [Claude Code hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code CLI --settings flag](https://code.claude.com/docs/en/cli-reference.md)
- [cmux status API](https://cmux.com/docs/api)
- [OSC escape sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
