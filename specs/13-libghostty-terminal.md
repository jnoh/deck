---
status: done
priority: p1
---

# Spec: Replace SwiftTerm with libghostty

## Goal

Replace SwiftTerm's terminal rendering with libghostty for GPU-accelerated rendering, better font handling, and modern terminal protocol support.

## Background

The product spec calls out libghostty as a fallback if SwiftTerm's rendering quality is insufficient. libghostty is the core terminal library extracted from the Ghostty terminal emulator. It provides a C API with Metal-based GPU rendering on macOS, SIMD-optimized VT parsing, full Kitty keyboard/graphics protocol support, and production-proven terminal emulation.

Multiple macOS apps already embed it successfully:
- **Muxy** — SwiftUI terminal multiplexer (Homebrew-installable)
- **Kytos** — native macOS terminal, ~1500 lines of Swift on top of GhosttyKit xcframework
- **OrbStack** — Docker & Linux for macOS

SwiftTerm limitations that libghostty addresses:
- CPU-only rendering (libghostty uses Metal)
- Missing DEC Private Mode 2031 / Kitty keyboard protocol (causes the `DECSET 2031` warnings we see)
- Simpler font rendering (libghostty uses CoreText with advanced shaping)
- No GPU-accelerated scrolling

## Acceptance Criteria

- [ ] libghostty integrated via SPM (pre-built xcframework from libghostty-spm or built from source)
- [ ] `GhosttyTerminalView` — an `NSViewRepresentable` wrapping libghostty's Metal-backed terminal surface
- [ ] Each session instance gets its own `ghostty_surface_t` with independent state
- [ ] PTY spawning delegated to libghostty (replaces our manual `bash -c` script approach)
- [ ] Keyboard input flows through libghostty's key encoding (fixes Kitty protocol warnings)
- [ ] CJK/emoji input works via `NSTextInputClient` integration
- [ ] Terminal renders at native refresh rate (120fps on ProMotion displays)
- [ ] Copy/paste works (Cmd+C/V in terminal)
- [ ] Scrollback works with smooth GPU-accelerated scrolling
- [ ] Window resize propagates to terminal (proper SIGWINCH)
- [ ] SwiftTerm dependency removed from Package.swift
- [ ] Existing tests still pass (session lifecycle, config, health monitor are unaffected)
- [ ] Visual verification: launch app, create session, confirm terminal renders correctly

## Out of Scope

- Custom terminal themes/color schemes (future spec)
- Shell integration features (prompt detection, etc.)
- Building libghostty from Zig source in CI (use pre-built xcframework)

## Approach

### Phase 1: Add libghostty dependency

Add the pre-built GhosttyKit xcframework via SPM. This avoids requiring a Zig compiler in the build chain.

```swift
// Package.swift
.binaryTarget(
    name: "GhosttyKit",
    url: "...",  // libghostty-spm release URL
    checksum: "..."
)
```

Required link frameworks: Metal, Carbon, CoreText.

### Phase 2: Create GhosttyTerminalView

Build an `NSViewRepresentable` that:

1. Creates a `ghostty_app_t` (singleton, manages global state)
2. Creates a `ghostty_surface_t` per session (individual terminal instance)
3. Attaches a `CAMetalLayer` for GPU rendering
4. Implements `NSTextInputClient` for keyboard/IME input
5. Sets up callbacks for clipboard, window management, and actions

Reference implementation: Kytos project architecture.

Key C API types from `ghostty.h`:
- `ghostty_app_t` — app instance, owns config and surfaces
- `ghostty_surface_t` — single terminal surface with its own PTY
- `ghostty_config_t` — terminal configuration (font, colors, behavior)

### Phase 3: Wire into AppCoordinator

Replace `TerminalSessionView` with `GhosttyTerminalView`:
- `AppCoordinator.startSession()` creates a ghostty surface with the session's startup command
- Surface handles PTY spawning internally (no more temp script files)
- Process exit detected via ghostty callback → `handleProcessExit()`

### Phase 4: Remove SwiftTerm

- Remove `SwiftTerm` from Package.swift dependencies
- Remove `LocalSessionRunner` (no longer needed — ghostty owns the PTY)
- Remove `TerminalSessionView` (replaced by `GhosttyTerminalView`)
- Update `LocalSessionRunnerTests` to test via ghostty or remove PTY-specific tests

## Dependencies

- Spec 07 (Terminal View) — this replaces it
- Pre-built GhosttyKit xcframework availability

## Risks

- **API instability**: libghostty's C API is not yet tagged stable. Pin to a specific commit/version.
- **xcframework availability**: If libghostty-spm doesn't have a release, we may need to build from Zig source, which adds Zig 0.15 as a build dependency.
- **Metal requirement**: GPU rendering requires Metal, which is available on all macOS 14+ hardware but may not work in some CI environments.

## Blocked: Architecture Mismatch (2026-04-13)

**Attempted and reverted.** libghostty's `ghostty_app_new` takes over the entire macOS app — it replaces the menu bar (shows "Ghostty" instead of "Deck") and manages its own windows. This is by design: libghostty is built for apps that ARE terminals (Muxy, Kytos, Ghostty itself), not apps that EMBED a terminal alongside other UI like a sidebar.

Deck needs a terminal view that lives inside a NavigationSplitView alongside a session sidebar. libghostty doesn't support this — its app singleton assumes it owns the process.

**Unblocking paths:**
1. Wait for libghostty to offer a view-only embedding mode (no app takeover)
2. Use libghostty-vt (the low-level VT parser) with a custom Metal renderer, keeping SwiftTerm's view architecture
3. Contribute an embedding mode upstream

For now, SwiftTerm works correctly for Deck's architecture.

## References

- [libghostty announcement](https://mitchellh.com/writing/libghostty-is-coming)
- [Ghostty repo](https://github.com/ghostty-org/ghostty) — `include/ghostty.h` for C API
- [Kytos blog post](https://jwintz.gitlabpages.inria.fr/jwintz/blog/2026-03-14-kytos-terminal-on-ghostty/) — detailed macOS integration walkthrough
- [Muxy](https://github.com/muxy-app/muxy) — SwiftUI multiplexer using libghostty
- [Ghostling](https://github.com/ghostty-org/ghostling) — minimal C implementation
- [awesome-libghostty](https://github.com/Uzaaft/awesome-libghostty) — community projects
