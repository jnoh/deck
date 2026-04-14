---
status: done
priority: p1
---

# Spec: Health Monitor

## Goal

Background polling of health check commands, transitioning sessions between `running` and `degraded`.

## Background

Each session defines a `health.command` and `health.interval_seconds`. The health command runs locally for both session types. Exit 0 = healthy, non-zero = degraded. See `docs/product-spec.md` — Health section and States.

## Acceptance Criteria

- [ ] `HealthMonitor` polls each running session's health command at the configured interval
- [ ] Exit 0 → session stays/transitions to `running`
- [ ] Non-zero exit → session transitions to `degraded`
- [ ] Degraded session whose health check starts passing again → transitions back to `running`
- [ ] Health polling starts when a session enters `running` state
- [ ] Health polling stops when a session leaves `running` or `degraded` state
- [ ] Default health command (`"true"`) always passes
- [ ] Health check timeout: if command doesn't complete within the interval, treat as failure
- [ ] Health checks run as local shell commands via `/bin/bash -c`
- [ ] Multiple sessions' health checks run concurrently (not blocking each other)

## Out of Scope

- Reconnection logic for remote sessions (spec 09)
- UI indicators (spec 06 uses session state)

## Approach

- Use Swift concurrency (`Task`, `Task.sleep`) for polling loops
- One `Task` per session, stored on the `Session` or `HealthMonitor`
- Cancel tasks on session state change
- `Process` with a timeout for running the health command

## Dependencies

- Spec 02 (Session State Machine)
- Spec 03 (Local Session Lifecycle) — health monitoring only meaningful for running sessions
