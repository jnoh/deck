---
status: done
priority: p0
---

# Spec: Terminal View

## Goal

Integrate SwiftTerm to render terminal output for active sessions in the content area.

## Background

Each active session has a SwiftTerm instance attached to its PTY. Clicking a session in the sidebar swaps which terminal view is visible. See `docs/product-spec.md` — Terminal Content Area.

## Acceptance Criteria

- [ ] SwiftTerm `LocalProcessTerminalView` (or equivalent) renders terminal output for a local session's PTY
- [ ] One SwiftTerm instance per active session (created on session start, destroyed on stop)
- [ ] Selecting a session in the sidebar shows its terminal view in the content area
- [ ] Switching sessions preserves scrollback and terminal state of the previously selected session
- [ ] Terminal supports standard interactions: scrollback, text selection, copy/paste
- [ ] Input typed in the terminal is sent to the PTY
- [ ] Empty state shown when no session is selected or selected session is stopped
- [ ] Starting state shows terminal output of the startup process in real-time
- [ ] SwiftTerm view is wrapped in `NSViewRepresentable` for SwiftUI integration

## Out of Scope

- Remote session terminal attachment (spec 08)
- Terminal theming/customization

## Approach

- Wrap SwiftTerm's `TerminalView` (AppKit) in an `NSViewRepresentable`
- `TerminalViewContainer` manages the mapping of session → SwiftTerm instance
- On session selection change, swap which `TerminalView` is displayed
- Connect SwiftTerm to the PTY fd from the local session runner

## Dependencies

- Spec 03 (Local Session Lifecycle) — needs PTY file descriptors
- Spec 06 (Sidebar UI) — needs session selection binding
