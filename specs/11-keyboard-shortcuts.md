---
status: done
priority: p2
---

# Spec: Keyboard Shortcuts

## Goal

Implement keyboard shortcuts for session navigation and actions.

## Background

Power users need fast keyboard-driven navigation between sessions. See `docs/product-spec.md` — Keyboard Shortcuts.

## Acceptance Criteria

- [ ] `Cmd+1` through `Cmd+9` jump to session by position in the sidebar list
- [ ] `Cmd+[` selects previous session, `Cmd+]` selects next session
- [ ] `Cmd+N` creates a new session definition (scaffolds TOML, opens in editor)
- [ ] `Cmd+W` stops the currently selected session
- [ ] `Cmd+R` restarts the currently selected session
- [ ] Shortcuts are disabled when no session is selected (where applicable)
- [ ] Shortcuts don't conflict with terminal input (terminal view should not consume these)
- [ ] Shortcuts are listed in the app's menu bar menus (standard macOS discoverability)

## Out of Scope

- Configurable global hotkey to bring Deck to front (future consideration)
- Custom key binding

## Approach

- Use SwiftUI `.keyboardShortcut()` modifiers on menu commands
- Add a proper `CommandMenu` or extend the default menu bar with keyboard shortcut entries
- Ensure SwiftTerm doesn't swallow Cmd-key combinations

## Dependencies

- Spec 06 (Sidebar UI) — session selection
- Spec 02 (Session State Machine) — start/stop/restart actions
