---
status: done
priority: p2
---

# Spec: Remote Session Reconnection

## Goal

Automatically reconnect to remote sessions when SSH drops, leveraging the persistent remote tmux session.

## Background

When an SSH connection drops, the remote tmux session keeps the process alive. Deck should detect the drop, check if the remote is still healthy, and auto-reconnect if possible. See `docs/product-spec.md` — Reconnection (remote only).

## Acceptance Criteria

- [ ] Detect unexpected SSH PTY process exit (as opposed to intentional teardown)
- [ ] On unexpected exit, run the session's health check
- [ ] If health check passes: auto-reconnect by re-running the SSH tmux attach command
- [ ] New SwiftTerm instance is created and swapped in for the reconnected session
- [ ] Session remains in `running` state during successful reconnection
- [ ] If health check fails: transition session to `degraded`
- [ ] Degraded sessions show a reconnect button in the sidebar
- [ ] Manual reconnect button triggers the same reconnection flow
- [ ] Reconnection attempts have a retry limit or backoff to avoid tight loops
- [ ] User is not interrupted during auto-reconnect (no modal dialogs)

## Out of Scope

- SSH keep-alive configuration
- Network state monitoring (rely on process exit detection)

## Approach

- Monitor the SSH `Process.terminationHandler`
- Distinguish intentional teardown (flag set before kill) from unexpected exit
- Reuse `RemoteSessionRunner` attach logic for reconnection
- Exponential backoff on repeated reconnection failures

## Dependencies

- Spec 05 (Health Monitor) — health check on SSH drop
- Spec 08 (Remote Session Lifecycle) — SSH attach infrastructure
