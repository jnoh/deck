---
status: done
priority: p2
---

# Spec: Menu Bar

## Goal

Add a persistent menu bar icon with a dropdown showing session status and quick actions.

## Background

Deck lives in the menu bar for quick access. The dropdown shows all sessions with status dots and provides Start All / Stop All actions. See `docs/product-spec.md` — Menu Bar.

## Acceptance Criteria

- [ ] Persistent menu bar icon (visible even when app window is closed)
- [ ] Dropdown lists all sessions with status dot (same colors as sidebar)
- [ ] Clicking a session brings Deck to front with that session selected
- [ ] "Start All" action starts all stopped sessions
- [ ] "Stop All" action stops all running/degraded sessions
- [ ] Menu bar updates reactively as session states change
- [ ] Menu bar icon indicates overall status (e.g., all healthy vs. some degraded)
- [ ] "Quit Deck" option in menu

## Out of Scope

- Menu bar-only mode (hiding the dock icon)
- Notifications

## Approach

- Use `MenuBarExtra` (macOS 13+) in SwiftUI
- Observe `SessionManager` for reactive menu updates
- Use `NSApplication` to bring window to front and select session

## Dependencies

- Spec 02 (Session State Machine) — session list and states
- Spec 06 (Sidebar UI) — session selection mechanism
