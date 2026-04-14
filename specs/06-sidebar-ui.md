---
status: done
priority: p0
---

# Spec: Sidebar UI

## Goal

Build the sidebar showing sessions grouped by state with status indicators and context menus.

## Background

The sidebar is the primary navigation for Deck. Sessions are grouped into sections by state and each row shows icon, name, status dot, and description. See `docs/product-spec.md` — Sidebar and Status Indicators.

## Acceptance Criteria

- [ ] Sidebar uses `NavigationSplitView` with a list of sessions
- [ ] Sessions grouped into sections: Running, Degraded, Starting/Provisioning, Stopped
- [ ] Each row displays: icon (emoji), session name, status dot (colored circle), description
- [ ] Status dot colors: green = running, yellow = degraded, gray = stopped
- [ ] Pulsing animation on status dot for transitional states (provisioning, starting, stopping, deprovisioning)
- [ ] Sessions sorted alphabetically within each group
- [ ] Selecting a session updates the content area (selection binding)
- [ ] Right-click context menu per session: Start, Stop, Restart, Edit Config (opens TOML in default editor), Show in Finder
- [ ] Context menu items are enabled/disabled based on session state (e.g., can't Start a running session)
- [ ] "+" button at bottom to create a new session (scaffolds a TOML template and opens in editor)
- [ ] Empty state when no sessions are configured

## Out of Scope

- Terminal content area (spec 07)
- Menu bar integration (spec 10)
- Keyboard shortcuts for navigation (spec 11)

## Approach

- `NavigationSplitView` with sidebar and detail
- `SessionRowView` for individual rows
- Observe `SessionManager` for reactive updates
- Use `NSWorkspace.shared.open()` for "Edit Config" and "Show in Finder"
- "+" button uses a template TOML string, writes to config dir, opens in editor

## Dependencies

- Spec 02 (Session State Machine) — needs `Session` and `SessionManager` observable models
