---
status: done
priority: p0
---

# Spec: Local Session Lifecycle

## Goal

Implement PTY spawning, process management, and teardown for local sessions.

## Background

Local sessions are the simpler of the two session types. Deck spawns a PTY directly — no tmux, no multiplexer. The app owns the process. If the app quits, local sessions die. See `docs/product-spec.md` — Local Startup and Teardown.

## Acceptance Criteria

- [ ] Compose `startup.steps` into a single shell script written to a temp file
- [ ] Spawn a PTY running `bash -l -c 'cd <working_dir> && bash /tmp/deck-<name>.sh'`
- [ ] PTY file descriptors are accessible for later SwiftTerm attachment
- [ ] Session transitions: `stopped → starting → running` on successful spawn
- [ ] Teardown: run teardown commands, then terminate the PTY process
- [ ] Session transitions: `running → stopping → stopped` on teardown
- [ ] Restart: teardown then startup in sequence
- [ ] Tilde expansion works for `working_dir`
- [ ] Temp script is cleaned up on teardown
- [ ] Process termination is detected (unexpected exit sets state appropriately)
- [ ] App quit terminates all local session processes

## Out of Scope

- Terminal UI / SwiftTerm rendering (spec 07)
- Health checking (spec 05)
- Remote sessions (spec 08)

## Approach

- Use `Foundation.Process` with `posix_openpt` / `forkpty` for PTY spawning, or leverage SwiftTerm's `LocalProcess` if it provides this
- `LocalSessionRunner` class that owns the PTY process for a single session
- Monitor process exit via `Process.terminationHandler` or `waitpid`
- Store PTY master fd on the `Session` for later SwiftTerm attachment

## Dependencies

- Spec 01 (Config Parsing)
- Spec 02 (Session State Machine)
