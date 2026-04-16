---
status: done
priority: p1
---

# Spec: Dynamic Select Params

## Goal

Allow `.deck` package params to be dropdowns whose options come from a shell command, so users pick from real data (workspaces, branches, hosts) instead of typing free text.

## Background

Params today are always free-text `TextField`s. A `remote-claude` package has `SSH_HOST` as a text field — the user has to know and type the exact hostname. If the package could declare "run `coder list` and show the results as a picker," the creation flow becomes point-and-click.

This builds on the param system introduced in spec 15 (Session Packages).

## Design

### TOML Schema

Two new optional fields on `[[params]]`:

```toml
[[params]]
key = "WORKSPACE"
label = "Workspace"
type = "select"                    # "text" (default) | "select"
source = "coder list -o json | jq '[.[] | {value: .name, label: .name}]'"
required = true
```

- `type` defaults to `"text"` (current behavior). `"select"` renders a `Picker`.
- `source` is a shell command. Only meaningful when `type = "select"`.

### Source Command Contract

The command writes to stdout a JSON array of objects:

```json
[
  {"value": "my-workspace", "label": "my-workspace (running)"},
  {"value": "other-ws", "label": "other-ws (stopped)"}
]
```

- `value` — injected as the env var, must be a string.
- `label` — displayed in the picker.

### Source Execution Context

The source command runs with:
- Shell: `/bin/bash -c "<source>"`
- Working directory: the `.deck` package directory
- `DECK_PACKAGE_DIR` set
- Env vars from params declared *above* this one that the user has already filled in (enables basic chaining — e.g., pick a host, then list workspaces on that host)
- Timeout: 15 seconds
- Stderr is captured for error display but not parsed

### CreateSessionSheet Behavior

For `type = "select"` params:
- Render a `Picker` (dropdown) instead of a `TextField`.
- On sheet appear, kick off the source command asynchronously.
- **Loading**: show a disabled picker with the placeholder text (or "Loading...").
- **Success**: populate the picker. If `default` matches a value, pre-select it.
- **Error**: show inline error text with the stderr/exit-code. Provide a retry button. Do not fall back to a text field — the package author chose `select` because the value must be one of the options.
- **Timeout**: treat as error with message "Command timed out after 15s".
- The "Create" button remains disabled while any required select param is loading or errored.

### Model Changes

`SessionParam` gains two optional fields:

```swift
public struct SessionParam: Codable, Sendable {
    public let key: String
    public let label: String
    public var placeholder: String?
    public var `default`: String?
    public var required: Bool?
    public var type: String?      // "text" | "select", defaults to "text"
    public var source: String?    // shell command for select options
    
    public var isSelect: Bool { type == "select" }
    public var isRequired: Bool { `required` ?? false }
    public var defaultValue: String { `default` ?? "" }
}
```

No changes to `SessionConfig.paramValues`, `AppCoordinator`, env var injection, or `TerminalSessionView`. The downstream flow is unchanged — a select param produces a `[String: String]` entry just like a text param.

## Acceptance Criteria

- [ ] `SessionParam` has `type` and `source` fields, decoded from TOML
- [ ] `CreateSessionSheet` renders a `Picker` for `type = "select"` params
- [ ] Source command runs async on sheet appear with 15s timeout
- [ ] Loading state: disabled picker with placeholder text
- [ ] Error state: inline error message with retry button
- [ ] Successful options populate the picker; `default` pre-selects if matched
- [ ] Already-filled upstream param values are passed as env vars to the source command
- [ ] `DECK_PACKAGE_DIR` is set in the source command's environment
- [ ] Text params (`type = "text"` or omitted) unchanged — no regression
- [ ] Verify loop passes (`swift build && swift test`)
- [ ] Visual verification: create a test `.deck` package with a select param, open the sheet, confirm picker renders with options

## Out of Scope

- Reactive param chaining (re-running source when an upstream param changes)
- Caching / TTL for source results
- Multi-select params
- Inline "new" option (e.g., create a workspace from the picker)
- Autocomplete / searchable combobox (standard `Picker` is sufficient for v1)

## Approach

1. **Model** — Add `type` and `source` to `SessionParam` in `SessionConfig.swift`
2. **Command runner** — Small async function that runs a shell command, captures stdout/stderr, enforces timeout, parses JSON into `[ParamOption]` (`value` + `label`)
3. **CreateSessionSheet** — Add `@State` for loading/options/error per select param. On appear, fire source commands. Render `Picker` for select, `TextField` for text. Wire up retry.
4. **Test package** — Add or update a bundled template to use a select param for verification

## Dependencies

- Spec 15 (Session Packages) — done

## Notes

- The structured output format (`{value, label}`) was chosen over simple line-per-option to avoid a future migration. Package authors who want the simple case write `jq '[.[] | {value: ., label: .}]'`.
- Reactive chaining (re-run source when upstream changes) is a natural follow-up but adds significant UI complexity. For now, source commands can *read* upstream values but won't re-trigger.
