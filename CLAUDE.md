# Deck

Native macOS app for orchestrating long-running CLI sessions. See `docs/product-spec.md` for full spec.

## Tech Stack

- Swift 6.0, SwiftUI, macOS 14+
- SPM dependencies: TOMLKit
- Terminal rendering: libghostty (GhosttyKit xcframework, Metal GPU rendering)
- First-time setup: `./scripts/setup.sh` (downloads GhosttyKit.xcframework via gh CLI)
- Build: `swift build` or open `Package.swift` in Xcode

## Verify Loop

```bash
swift build 2>&1 && swift test 2>&1
```

Run after every meaningful change and before committing.

### Visual Verification

After any UI change, launch the app, take a screenshot, and read it to verify visually before reporting done. Do not ship UI changes without visual confirmation.

```bash
# Launch
pkill -f ".build/debug/Deck" 2>/dev/null || true; sleep 0.3
.build/debug/Deck &
sleep 2

# Screenshot
screencapture -x /tmp/deck-screenshot.png

# Interact (via AppleScript or cliclick)
osascript -e 'tell application "System Events" to tell process "Deck" to set frontmost to true'
cliclick rc:<x>,<y>   # right-click at coordinates

# Kill
pkill -f ".build/debug/Deck"
```

Helper script at `scripts/ui-test.sh` provides: `launch`, `kill`, `screenshot`, `click-add`, `select-blueprint N`, `right-click N`, `list-ui`, `type TEXT`.

Key accessibility paths:
- "+" button: `menu button "Add" of group 1 of toolbar 1 of window 1`
- Sidebar rows: use `entire contents of window 1` to find `row` elements and their positions
- Context menu: `cliclick rc:<x>,<y>` then find `menu item` elements

## Commit Hygiene

- Commits should be atomic and focused on a single concern
- Write commit messages that explain *why*, not *what*
- Run the verify loop before committing
- Don't commit generated files or build artifacts

## Spec-Driven Workflow

1. Specs live in `specs/` using the template at `specs/_template.md`
2. Each spec has a status: `draft` → `ready` → `in_progress` → `done`
3. Use `/sdlc:spec-author` to create new specs
4. Use `/sdlc:spec-execute` to implement a ready spec
5. Use `/sdlc:judge-pass` to verify completed work against acceptance criteria
6. Use `/sdlc:doc-sync` to update architecture docs after completion
