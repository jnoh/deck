---
status: done
priority: p1
---

# Spec: Config Directory Watcher

## Goal

Watch `~/.config/deck/sessions/` for file changes and live-reload session definitions.

## Background

The app watches the config directory and live-reloads on changes. Adding, modifying, or removing a TOML file should update the session list without restarting the app. See `docs/product-spec.md` — Session Definitions.

## Acceptance Criteria

- [ ] `ConfigWatcher` monitors `~/.config/deck/sessions/` for file system events
- [ ] New `.toml` file added → new session appears in `SessionManager` (state: stopped)
- [ ] Existing `.toml` file modified → session config is updated (if session is stopped, update in place; if running, mark config as stale for next restart)
- [ ] `.toml` file deleted → session is removed from `SessionManager` (if stopped) or marked for removal (if running)
- [ ] Non-`.toml` files are ignored
- [ ] Invalid TOML files are handled gracefully (logged, not crashed)
- [ ] Watcher starts automatically on app launch
- [ ] Watcher handles the config directory not existing (creates it)

## Out of Scope

- Editing TOML files from within the app
- Config validation UI

## Approach

- Use `DispatchSource.makeFileSystemObjectSource` or `FSEvents` via `CoreServices`
- Debounce rapid changes (e.g., editor save triggers multiple events)
- On event: re-scan directory, diff against current sessions, apply changes to `SessionManager`

## Dependencies

- Spec 01 (Config Parsing)
- Spec 02 (Session State Machine)
