---
status: done
priority: p0
---

# Spec: Session State Machine

## Goal

Define the session lifecycle state machine and a `SessionManager` that owns all session state.

## Background

Sessions transition through: `stopped → provisioning → starting → running ⇄ degraded → stopping → deprovisioning → stopped`. Local sessions skip provisioning/deprovisioning. The state machine is central to the sidebar UI, health monitoring, and lifecycle orchestration.

## Acceptance Criteria

- [ ] `SessionState` enum with cases: `stopped`, `provisioning`, `starting`, `running`, `degraded`, `stopping`, `deprovisioning`
- [ ] `Session` observable model holding: config, current state, and associated process/PTY handle (optional at this stage)
- [ ] `SessionManager` as an `@Observable` class holding an array of `Session` objects
- [ ] `SessionManager.loadSessions()` uses `ConfigLoader` to populate sessions from config directory
- [ ] Valid state transitions are enforced (e.g., can't go from `stopped` directly to `running`)
- [ ] Local sessions skip `provisioning` and `deprovisioning` states
- [ ] Sessions are grouped by state for sidebar consumption (computed properties)
- [ ] Unit tests for valid and invalid state transitions

## Out of Scope

- Actually starting/stopping processes (spec 03)
- Health check polling (spec 05)
- UI (specs 06, 07)

## Approach

- `SessionState` enum with a `validTransitions` method or similar guard
- `Session` class conforming to `Observable` (Observation framework)
- `SessionManager` as the single source of truth, injected into the SwiftUI environment
- State transition methods on `Session`: `transitionTo(_ newState:) throws`

## Dependencies

- Spec 01 (Config Parsing) — needs `SessionConfig` models
