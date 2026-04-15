import SwiftUI
import AppKit
import GhosttyKit

// MARK: - Ghostty Service Singleton

/// Manages the global ghostty_app_t. Ghostty is a service, NOT the app controller.
public final class GhosttyService: @unchecked Sendable {
    public static let shared = GhosttyService()

    private(set) var app: ghostty_app_t?
    private var initialized = false

    /// Maps surface userdata pointer → Session, for routing status updates
    private var surfaceSessionMap: [UnsafeMutableRawPointer: Session] = [:]
    private let mapLock = NSLock()

    func registerSurface(_ view: GhosttyTerminalNSView, session: Session) {
        let ptr = Unmanaged.passUnretained(view).toOpaque()
        mapLock.lock()
        surfaceSessionMap[ptr] = session
        mapLock.unlock()
    }

    func unregisterSurface(_ view: GhosttyTerminalNSView) {
        let ptr = Unmanaged.passUnretained(view).toOpaque()
        mapLock.lock()
        surfaceSessionMap.removeValue(forKey: ptr)
        mapLock.unlock()
    }

    func session(forSurface surface: ghostty_surface_t) -> Session? {
        let ptr = ghostty_surface_userdata(surface)
        guard let ptr = ptr else { return nil }
        mapLock.lock()
        let session = surfaceSessionMap[ptr]
        mapLock.unlock()
        return session
    }

    private init() {}

    /// Path where a session's status file lives
    static func statusFilePath(for sessionId: String) -> String {
        "/tmp/deck-\(sessionId).status"
    }

    public func ensureInitialized() {
        guard !initialized else { return }
        initialized = true

        // ghostty_init must be called before any other ghostty function
        let initResult = ghostty_init(0, nil)
        guard initResult == GHOSTTY_SUCCESS else {
            print("ghostty_init failed with code \(initResult)")
            return
        }

        let config = ghostty_config_new()!

        // Load user's default ghostty config (font, theme, etc.)
        ghostty_config_load_default_files(config)

        // Apply Deck-specific overrides via a temp config file
        let deckConfig = """
        window-padding-x = 8
        window-padding-y = 4,0
        window-padding-balance = true
        """
        let tmpPath = NSTemporaryDirectory() + "deck-ghostty.conf"
        try? deckConfig.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        tmpPath.withCString { ghostty_config_load_file(config, $0) }

        ghostty_config_finalize(config)

        var rt = ghostty_runtime_config_s()
        rt.userdata = Unmanaged.passUnretained(self).toOpaque()
        rt.supports_selection_clipboard = false

        // Wakeup: no-op, rendering is driven by the surface/Metal layer
        rt.wakeup_cb = { _ in }

        // Action callback: intercept ALL actions, don't let ghostty handle any.
        // Returning true = "I handled it" which prevents ghostty from doing its own thing
        // (like setting up menu bars, creating windows, etc.)
        rt.action_cb = { app, target, action in
            return GhosttyService.handleAction(target: target, action: action)
        }

        // Clipboard: handle read/write ourselves
        rt.read_clipboard_cb = { userdata, clipboard, state in
            // Return false = no clipboard data provided
            return false
        }
        rt.confirm_read_clipboard_cb = nil

        rt.write_clipboard_cb = { _, clipboard, contents, count, _ in
            guard count > 0, let contents = contents else { return }
            let content = contents.pointee
            if let data = content.data {
                let str = String(cString: data)
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(str, forType: .string)
                }
            }
        }

        rt.close_surface_cb = { _, _ in }

        app = ghostty_app_new(&rt, config)
        ghostty_config_free(config)
    }

    /// Handle all ghostty actions ourselves. Return true to prevent ghostty from acting.
    private static func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            return true
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            return true  // Block notifications
        case GHOSTTY_ACTION_NEW_WINDOW,
             GHOSTTY_ACTION_NEW_TAB,
             GHOSTTY_ACTION_NEW_SPLIT:
            return true  // We manage our own windows/tabs
        case GHOSTTY_ACTION_CLOSE_ALL_WINDOWS,
             GHOSTTY_ACTION_CLOSE_TAB:
            return true  // We handle surface lifecycle
        case GHOSTTY_ACTION_QUIT:
            return true  // We handle quit
        case GHOSTTY_ACTION_TOGGLE_FULLSCREEN:
            return true  // We handle fullscreen
        default:
            // For rendering-related actions, let ghostty handle them
            return false
        }
    }
}

// MARK: - Terminal Surface NSView

public class GhosttyTerminalNSView: NSView {
    nonisolated(unsafe) private var surface: ghostty_surface_t?
    private var trackingArea: NSTrackingArea?
    nonisolated(unsafe) var onProcessExit: ((Int32?) -> Void)?
    nonisolated(unsafe) var session: Session?
    nonisolated(unsafe) private var exitPollTimer: Timer?
    nonisolated(unsafe) private var statusPollTimer: Timer?

    override public var acceptsFirstResponder: Bool { true }
    override public var isFlipped: Bool { true }

    override public init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    public func startTerminal(workingDir: String, initialInput: String?, session: Session?) {
        self.session = session
        GhosttyService.shared.ensureInitialized()
        guard let app = GhosttyService.shared.app else { return }

        // Register this view → session mapping for status routing
        if let session = session {
            GhosttyService.shared.registerSurface(self, session: session)
        }

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.scale_factor = Double(window?.backingScaleFactor ?? 2.0)

        // Tell ghostty this is a split pane, NOT a standalone window.
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

        let wdCStr = strdup(workingDir)
        surfaceConfig.working_directory = UnsafePointer(wdCStr)

        // Inject DECK_SESSION_ID via env vars
        var envKeepAlive: [UnsafeMutablePointer<CChar>] = []
        var envVarArray: [ghostty_env_var_s] = []

        if let session = session {
            let idKey = strdup("DECK_SESSION_ID")!
            let idVal = strdup(session.id)!
            envKeepAlive.append(contentsOf: [idKey, idVal])
            envVarArray.append(ghostty_env_var_s(key: idKey, value: idVal))

            let nameKey = strdup("DECK_SESSION_NAME")!
            let nameVal = strdup(session.displayName)!
            envKeepAlive.append(contentsOf: [nameKey, nameVal])
            envVarArray.append(ghostty_env_var_s(key: nameKey, value: nameVal))
        }

        // Write a `deck` CLI script to disk and put it on PATH
        let sessionId = session?.id ?? "unknown"
        let statusPath = GhosttyService.statusFilePath(for: sessionId)
        let binDir = "/tmp/deck-bin-\(sessionId)"
        try? FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)

        let q = "\\\""  // produces \" in the output file
        let deckScript = """
#!/bin/sh
_cmd="$1"; shift
_json=""
case "$_cmd" in
  status)
    _state="" _desc="" _icon=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --state) _state="$2"; shift 2;;
        --desc)  _desc="$2"; shift 2;;
        --icon)  _icon="$2"; shift 2;;
        *) shift;;
      esac
    done
    _json="{\(q)type\(q):\(q)status\(q)"
    [ -n "$_state" ] && _json="$_json,\(q)state\(q):\(q)$_state\(q)"
    [ -n "$_desc" ]  && _json="$_json,\(q)desc\(q):\(q)$_desc\(q)"
    [ -n "$_icon" ]  && _json="$_json,\(q)icon\(q):\(q)$_icon\(q)"
    _json="$_json}"
    ;;
  notify)
    _text="" _level="info"
    while [ $# -gt 0 ]; do
      case "$1" in
        --text)  _text="$2"; shift 2;;
        --level) _level="$2"; shift 2;;
        *) shift;;
      esac
    done
    _json="{\(q)type\(q):\(q)notify\(q),\(q)text\(q):\(q)$_text\(q),\(q)level\(q):\(q)$_level\(q)}"
    ;;
  title)
    _title="$*"
    _json="{\(q)type\(q):\(q)title\(q),\(q)text\(q):\(q)$_title\(q)}"
    ;;
  clear)
    _json="{\(q)type\(q):\(q)clear\(q)}"
    ;;
  exit)
    _json="{\(q)type\(q):\(q)exit\(q)}"
    ;;
  *) exit 1;;
esac
/bin/echo "$_json" >> '\(statusPath)'
"""
        let deckPath = "\(binDir)/deck"
        FileManager.default.createFile(atPath: deckPath, contents: deckScript.data(using: .utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deckPath)

        // Add the bin dir to PATH via env vars
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let pathKey = strdup("PATH")!
        let pathVal = strdup("\(binDir):\(currentPath)")!
        envKeepAlive.append(contentsOf: [pathKey, pathVal])
        envVarArray.append(ghostty_env_var_s(key: pathKey, value: pathVal))

        let idKey2 = strdup("DECK_SESSION_ID")!
        let idVal2 = strdup(sessionId)!
        envKeepAlive.append(contentsOf: [idKey2, idVal2])
        envVarArray.append(ghostty_env_var_s(key: idKey2, value: idVal2))

        // Add DECK_PACKAGE_DIR if this is a package
        if let packageDir = session?.config.packageDir {
            let pkgKey = strdup("DECK_PACKAGE_DIR")!
            let pkgVal = strdup(packageDir.path)!
            envKeepAlive.append(contentsOf: [pkgKey, pkgVal])
            envVarArray.append(ghostty_env_var_s(key: pkgKey, value: pkgVal))
        }

        // Use the user's default shell
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Build the startup wrapper script
        let startupPath = "/tmp/deck-start-\(sessionId).sh"
        var startupLines = "#!/bin/bash\n"

        if let startScript = session?.config.startScript {
            // Package with start.sh — the script controls the full lifecycle
            startupLines += "exec '\(startScript.path)'\n"
        } else if let input = initialInput {
            // Flat TOML — run steps then drop into interactive shell
            startupLines += input
            startupLines += "exec '\(userShell)' -l\n"
        } else {
            // No steps — just interactive shell
            startupLines += "exec '\(userShell)' -l\n"
        }

        FileManager.default.createFile(atPath: startupPath, contents: startupLines.data(using: .utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: startupPath)

        // Set the command to our wrapper script instead of using initial_input
        let cmdCStr = strdup(startupPath)
        surfaceConfig.command = UnsafePointer(cmdCStr)
        // No initial_input needed — the wrapper script handles everything

        // Keep env vars pointer alive through surface creation
        let envPtr = UnsafeMutablePointer<ghostty_env_var_s>.allocate(capacity: envVarArray.count)
        for (i, envVar) in envVarArray.enumerated() {
            envPtr[i] = envVar
        }
        surfaceConfig.env_vars = envPtr
        surfaceConfig.env_var_count = envVarArray.count

        surface = ghostty_surface_new(app, &surfaceConfig)

        free(wdCStr)
        free(cmdCStr)
        envPtr.deallocate()
        for ptr in envKeepAlive { free(ptr) }

        updateTrackingAreas()
        startExitPolling()
        startStatusPolling()
    }

    public func destroySurface() {
        exitPollTimer?.invalidate()
        exitPollTimer = nil
        statusPollTimer?.invalidate()
        statusPollTimer = nil
        GhosttyService.shared.unregisterSurface(self)
        if let surface = surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
        // Clean up temp files
        if let session = session {
            let id = session.id
            try? FileManager.default.removeItem(atPath: GhosttyService.statusFilePath(for: id))
            try? FileManager.default.removeItem(atPath: "/tmp/deck-bin-\(id)")
            try? FileManager.default.removeItem(atPath: "/tmp/deck-start-\(id).sh")
            try? FileManager.default.removeItem(atPath: "/tmp/deck-title-\(id)")
        }
    }

    // MARK: - Layout & Rendering

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let surface = surface else { return }
        let scale = Double(window?.backingScaleFactor ?? 2.0)
        ghostty_surface_set_content_scale(surface, scale, scale)
        let size = bounds.size
        ghostty_surface_set_size(surface, UInt32(size.width * scale), UInt32(size.height * scale))
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface = surface else { return }
        let scale = Double(window?.backingScaleFactor ?? 2.0)
        ghostty_surface_set_size(surface, UInt32(newSize.width * scale), UInt32(newSize.height * scale))
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface = surface else { return }
        let scale = Double(window?.backingScaleFactor ?? 2.0)
        ghostty_surface_set_content_scale(surface, scale, scale)
        layer?.contentsScale = CGFloat(scale)
    }

    // MARK: - Focus

    override public func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface = surface {
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override public func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface = surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    // MARK: - Keyboard

    override public func keyDown(with event: NSEvent) {
        guard let surface = surface else { return }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.mods = translateMods(event.modifierFlags)
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = false

        // Set text for all characters except macOS special keys (arrows, function keys)
        // which produce Unicode private-use chars (U+F700+)
        if let chars = event.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ $0.value < 0xF700 }) {
            keyEvent.text = (chars as NSString).utf8String
        }

        ghostty_surface_key(surface, keyEvent)
    }

    override public func keyUp(with event: NSEvent) {
        guard let surface = surface else { return }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.mods = translateMods(event.modifierFlags)
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = false
        ghostty_surface_key(surface, keyEvent)
    }

    override public func insertText(_ insertString: Any) {
        guard let surface = surface, let text = insertString as? String else { return }
        text.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(strlen(cstr)))
        }
    }

    // MARK: - Mouse

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseDown(with event: NSEvent) {
        guard let surface = surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, translateMods(event.modifierFlags))
    }

    override public func mouseUp(with event: NSEvent) {
        guard let surface = surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, translateMods(event.modifierFlags))
    }

    override public func mouseMoved(with event: NSEvent) {
        guard let surface = surface else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let scale = Double(window?.backingScaleFactor ?? 2.0)
        ghostty_surface_mouse_pos(surface, pt.x * scale, pt.y * scale, translateMods(event.modifierFlags))
    }

    override public func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    override public func scrollWheel(with event: NSEvent) {
        guard let surface = surface else { return }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, Int32(translateMods(event.modifierFlags).rawValue))
    }

    // MARK: - Exit Polling

    private func startExitPolling() {
        exitPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, let surface = self.surface else {
                timer.invalidate()
                return
            }
            if ghostty_surface_process_exited(surface) {
                timer.invalidate()
                self.exitPollTimer = nil
                self.onProcessExit?(0)
            }
        }
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        guard let session = session else { return }
        let statusPath = GhosttyService.statusFilePath(for: session.id)

        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, self.session != nil else {
                timer.invalidate()
                return
            }
            guard let data = FileManager.default.contents(atPath: statusPath),
                  let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                return
            }
            // Remove the file so we don't re-process it
            try? FileManager.default.removeItem(atPath: statusPath)
            // Process each line as a separate JSON update
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            var shouldExit = false
            DispatchQueue.main.async { [weak self] in
                for line in lines {
                    if let update = StatusUpdate.parse(json: line) {
                        if update.type == .exit {
                            shouldExit = true
                            continue
                        }
                        if let newTitle = session.status.apply(update, sessionName: session.displayName) {
                            session.displayName = newTitle
                        }
                    }
                }
                if shouldExit {
                    self?.onProcessExit?(0)
                }
            }
        }
    }

    // MARK: - Helpers

    private func translateMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw: UInt32 = 0
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }
}

// MARK: - SwiftUI Wrapper

public struct TerminalSessionView: NSViewRepresentable {
    let session: Session
    let onProcessExit: ((Int32?) -> Void)?

    public init(session: Session, onProcessExit: ((Int32?) -> Void)? = nil) {
        self.session = session
        self.onProcessExit = onProcessExit
    }

    public func makeNSView(context: Context) -> GhosttyTerminalNSView {
        let view = GhosttyTerminalNSView(frame: .zero)
        view.onProcessExit = onProcessExit

        let config = session.config
        let initialInput = composeInitialInput(steps: config.startup.steps)
        view.startTerminal(workingDir: config.effectiveWorkingDir, initialInput: initialInput, session: session)

        // Transition to running
        if session.state == .starting {
            try? session.transitionTo(.running)
        }

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    public func updateNSView(_ nsView: GhosttyTerminalNSView, context: Context) {
        // Only grab focus if this view is visible (opacity > 0 means it's the selected session)
        // The ZStack keeps all terminal views alive — we must not let hidden ones steal focus
    }
    }

    public static func dismantleNSView(_ nsView: GhosttyTerminalNSView, coordinator: ()) {
        nsView.destroySurface()
    }

    private func composeInitialInput(steps: [String]) -> String? {
        if steps.isEmpty { return nil }
        return steps.map { $0 + "\n" }.joined()
    }
}
