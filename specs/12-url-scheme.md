---
status: done
priority: p2
---

# Spec: URL Scheme

## Goal

Handle `deck://` URLs to control sessions from external tools like Raycast, Shortcuts, and scripts.

## Background

URL schemes enable automation and integration with other macOS tools. See `docs/product-spec.md` — URL Scheme.

## Acceptance Criteria

- [ ] App registers `deck://` URL scheme in Info.plist
- [ ] `deck://start/<session-name>` starts the named session
- [ ] `deck://stop/<session-name>` stops the named session
- [ ] `deck://open/<session-name>` brings app to front with that session selected
- [ ] Unknown session names are handled gracefully (no crash, optionally show error)
- [ ] Unknown actions (not start/stop/open) are ignored gracefully
- [ ] URL handling works when app is already running and when it triggers app launch

## Out of Scope

- Authentication or access control for URL scheme
- Additional URL actions beyond start/stop/open

## Approach

- Use SwiftUI `.onOpenURL()` modifier on the main `WindowGroup`
- Parse URL path components to extract action and session name
- Route to `SessionManager` methods

## Dependencies

- Spec 02 (Session State Machine) — start/stop actions
- Spec 06 (Sidebar UI) — session selection for `open` action
