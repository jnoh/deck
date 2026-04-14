---
status: done
priority: p0
---

# Spec: TOML Config Parsing

## Goal

Parse session definition TOML files into Swift models, with validation and sensible defaults.

## Background

Every feature in Deck depends on loading session definitions from `~/.config/deck/sessions/*.toml`. This is the foundational data layer. See `docs/product-spec.md` — Session Definitions and Schema Reference.

## Acceptance Criteria

- [ ] `SessionConfig` model covers all fields from the schema reference (session, host, startup, teardown, health)
- [ ] Parses a valid local session TOML file into a `SessionConfig`
- [ ] Parses a valid remote session TOML file into a `SessionConfig`
- [ ] Applies defaults for optional fields (`icon` → `"▸"`, `health.command` → `"true"`, `health.interval_seconds` → `10`, `host.ready_timeout_seconds` → `120`, etc.)
- [ ] Returns clear errors for missing required fields (`session.name`, `session.type`)
- [ ] Returns clear errors for invalid `session.type` values (not `local` or `remote`)
- [ ] `ConfigLoader` discovers and parses all `.toml` files in a given directory
- [ ] `ConfigLoader` creates `~/.config/deck/sessions/` if it doesn't exist
- [ ] Unit tests for parsing, defaults, and error cases

## Out of Scope

- File watching / live reload (spec 04)
- Session state management (spec 02)
- Actually running sessions

## Approach

- Use TOMLKit for parsing
- Define `SessionConfig`, `HostConfig`, `StartupConfig`, `TeardownConfig`, `HealthConfig` as Swift structs
- `SessionType` enum: `.local`, `.remote`
- `ConfigLoader` class with `loadAll(from directory: URL) throws -> [SessionConfig]`
- Tilde expansion for `working_dir` paths

## Dependencies

None — this is the first spec.
