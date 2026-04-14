# Architecture

## Overview

Deck is a native macOS SwiftUI application built with Swift Package Manager. It manages long-running CLI sessions through PTY-based terminal views.

## Project Structure

```
Deck/
├── Package.swift                       # SPM manifest (SwiftTerm, TOMLKit)
├── Sources/
│   ├── DeckApp/                        # Executable target
│   │   ├── DeckApp.swift               # @main entry, WindowGroup + MenuBarExtra
│   │   └── MainView.swift              # Root view with NavigationSplitView
│   └── DeckLib/                        # Library target (all logic)
│       ├── SessionConfig.swift         # TOML config models + parsing
│       ├── ConfigLoader.swift          # Loads all .toml files from config dir
│       ├── ConfigWatcher.swift         # FSEvents watcher on config directory
│       ├── Session.swift               # Session state machine + SessionManager
│       ├── LocalSessionRunner.swift    # PTY spawning for local sessions
│       ├── RemoteSessionRunner.swift   # SSH + tmux for remote sessions
│       ├── ReconnectionManager.swift   # Auto-reconnect on SSH drops
│       ├── HealthMonitor.swift         # Background health check polling
│       ├── AppCoordinator.swift        # Wires everything together
│       ├── URLSchemeHandler.swift      # deck:// URL parsing
│       └── Views/
│           ├── SidebarView.swift       # Session list grouped by state
│           ├── SessionRowView.swift    # Individual session row
│           ├── StatusDotView.swift     # Colored/pulsing status indicator
│           ├── TerminalSessionView.swift # SwiftTerm NSViewRepresentable wrapper
│           ├── MenuBarView.swift       # Menu bar dropdown
│           └── DeckCommands.swift      # Keyboard shortcuts via Commands
├── Tests/
│   ├── ConfigParsingTests.swift        # 12 tests
│   ├── SessionTests.swift              # 18 tests
│   ├── LocalSessionRunnerTests.swift   # 6 tests
│   ├── ConfigWatcherTests.swift        # 4 tests
│   ├── HealthMonitorTests.swift        # 5 tests
│   ├── RemoteSessionRunnerTests.swift  # 7 tests
│   ├── ReconnectionManagerTests.swift  # 3 tests
│   └── URLSchemeTests.swift            # 7 tests
├── docs/
│   ├── product-spec.md                 # Full product specification
│   └── architecture.md                 # This file
└── specs/                              # Implementation specs (all done)
    ├── _template.md
    ├── 01-config-parsing.md
    ├── 02-session-state-machine.md
    ├── 03-local-session-lifecycle.md
    ├── 04-config-watcher.md
    ├── 05-health-monitor.md
    ├── 06-sidebar-ui.md
    ├── 07-terminal-view.md
    ├── 08-remote-session-lifecycle.md
    ├── 09-remote-reconnection.md
    ├── 10-menu-bar.md
    ├── 11-keyboard-shortcuts.md
    └── 12-url-scheme.md
```

## Key Components

### Config Layer
- **SessionConfig** — Codable Swift structs for all TOML fields with defaults
- **ConfigLoader** — Discovers and parses all `.toml` files from `~/.config/deck/sessions/`
- **ConfigWatcher** — DispatchSource-based FSEvents watcher with debouncing

### Session Lifecycle
- **Session** — Observable model with state machine (stopped → provisioning → starting → running ⇄ degraded → stopping → deprovisioning → stopped)
- **SessionManager** — Owns all sessions, provides grouped accessors for UI
- **LocalSessionRunner** — PTY spawning via SwiftTerm's LocalProcess, script composition
- **RemoteSessionRunner** — SSH + tmux lifecycle (provision, ready check, attach, teardown, deprovision)
- **ReconnectionManager** — Exponential backoff reconnection on SSH drops
- **HealthMonitor** — Concurrent per-session health check polling with Task-based cancellation

### UI Layer
- **MainView** — NavigationSplitView with sidebar + terminal detail
- **SidebarView** — Grouped session list with status dots and context menus
- **TerminalSessionView** — NSViewRepresentable wrapping SwiftTerm's LocalProcessTerminalView
- **MenuBarView** — MenuBarExtra dropdown with session list and quick actions
- **DeckCommands** — Cmd+1-9, Cmd+[/], Cmd+N/W/R keyboard shortcuts

### Integration
- **AppCoordinator** — Central orchestrator wiring config, sessions, health, and UI
- **URLSchemeHandler** — Parses `deck://start|stop|open/<session-name>` URLs

## Dependencies
- **SwiftTerm** (1.13.0) — Terminal emulation and PTY management
- **TOMLKit** (0.6.0) — TOML parsing via Codable
