---
status: done
priority: p1
---

# Spec: Remote Session Lifecycle

## Goal

Implement provisioning, SSH-based tmux session management, and deprovisioning for remote sessions.

## Background

Remote sessions SSH into a remote host and create an invisible tmux session there. tmux exists solely to keep the remote process alive across SSH drops. The user never interacts with tmux directly. See `docs/product-spec.md` — Remote Startup, Teardown, and Remote Session config.

## Acceptance Criteria

- [ ] Run `host.provision` locally if present; transition to `provisioning` state
- [ ] Poll `host.ready_check` until exit 0 or timeout; respect `host.ready_timeout_seconds`
- [ ] Timeout on ready check transitions to an error/stopped state
- [ ] Pipe startup script to remote host via SSH: write to `/tmp/deck-<name>.sh`
- [ ] Create remote tmux session: `<host.ssh> -- tmux new-session -d -s deck-<name> 'cd <working_dir> && bash /tmp/deck-<name>.sh'`
- [ ] Spawn local PTY running `<host.ssh> -- tmux attach -t deck-<name>` for terminal attachment
- [ ] Transition to `running` on successful attach
- [ ] Teardown: send teardown commands via SSH into tmux, kill remote tmux session
- [ ] Run `host.deprovision` locally if present; transition through `deprovisioning`
- [ ] Full state flow: `stopped → provisioning → starting → running → stopping → deprovisioning → stopped`
- [ ] Sessions without `host.provision` skip `provisioning`; without `host.deprovision` skip `deprovisioning`

## Out of Scope

- SSH reconnection on drop (spec 09)
- SSH key management or authentication UI

## Approach

- `RemoteSessionRunner` class mirroring `LocalSessionRunner` interface
- Use `Foundation.Process` for all local command execution (provision, ready_check, SSH)
- Ready check polling with `Task.sleep` and timeout tracking
- PTY spawning for the SSH attach command (reuse PTY infrastructure from spec 03)

## Dependencies

- Spec 01 (Config Parsing) — `HostConfig` fields
- Spec 02 (Session State Machine)
- Spec 03 (Local Session Lifecycle) — shared PTY infrastructure
