import Foundation
import SwiftUI

@Observable
public final class AppCoordinator: @unchecked Sendable {
    public let sessionManager = SessionManager()
    public let healthMonitor = HealthMonitor()
    public var selectedSessionId: String?

    private var configWatcher: ConfigWatcher?
    private var remoteRunners: [String: RemoteSessionRunner] = [:]
    private var actionObserver: NSObjectProtocol?

    public init() {}

    public func setup() {
        do {
            try sessionManager.loadBlueprints()
        } catch {
            print("Failed to load blueprints: \(error)")
        }

        configWatcher = ConfigWatcher(directory: ConfigLoader.defaultConfigDirectory) { [weak self] in
            DispatchQueue.main.async {
                self?.reloadBlueprints()
            }
        }
        try? configWatcher?.start()

        actionObserver = NotificationCenter.default.addObserver(
            forName: .deckSessionAction,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let action = info["action"] as? String,
                  let sessionId = info["session"] as? String else { return }
            self?.handleAction(action, sessionId: sessionId)
        }
    }

    /// Create a new session instance from a blueprint and mark it for starting
    public func createAndStartSession(from blueprint: SessionConfig) {
        let session = sessionManager.createInstance(from: blueprint)
        selectedSessionId = session.id
        startSession(session)
    }

    /// Create a session with a custom name and working directory
    public func createAndStartSession(from blueprint: SessionConfig, name: String, workingDir: String) {
        var customConfig = blueprint
        customConfig.overrideWorkingDir = workingDir
        let session = sessionManager.createInstance(from: customConfig)
        session.displayName = name
        selectedSessionId = session.id
        startSession(session)
    }

    public func startSession(_ session: Session) {
        guard session.state == .stopped else { return }

        switch session.config.type {
        case .local:
            // For local sessions, just transition state.
            // TerminalSessionView owns the PTY — it starts the process when it appears.
            try? session.transitionTo(.starting)

        case .remote:
            let runner = RemoteSessionRunner(session: session)
            remoteRunners[session.id] = runner
            Task {
                do {
                    try await runner.start()
                    healthMonitor.startMonitoring(session)
                } catch {
                    print("Failed to start remote session \(session.displayName): \(error)")
                }
            }
        }
    }

    public func stopSession(_ session: Session) {
        healthMonitor.stopMonitoring(name: session.id)

        switch session.config.type {
        case .local:
            // TerminalSessionView will be removed from the view tree,
            // which destroys the LocalProcessTerminalView and kills the PTY.
            if session.state != .stopped {
                try? session.transitionTo(.stopping)
                try? session.transitionTo(.stopped)
            }
        case .remote:
            if let runner = remoteRunners.removeValue(forKey: session.id) {
                Task { await runner.stop() }
            }
        }
    }

    public func restartSession(_ session: Session) {
        stopSession(session)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startSession(session)
        }
    }

    public func removeSession(_ session: Session) {
        stopSession(session)
        sessionManager.removeSession(session)
        if selectedSessionId == session.id {
            selectedSessionId = nil
        }
    }

    public func stopAllSessions() {
        for session in sessionManager.sessions where session.state.isActive || session.state.isTransitional {
            stopSession(session)
        }
    }

    public func startAllSessions() {
        for blueprint in sessionManager.blueprints {
            let hasRunning = sessionManager.sessions.contains {
                $0.config.name == blueprint.name && ($0.state.isActive || $0.state.isTransitional)
            }
            if !hasRunning {
                createAndStartSession(from: blueprint)
            }
        }
    }

    public func handleProcessExit(session: Session, exitCode: Int32?) {
        healthMonitor.stopMonitoring(name: session.id)
        remoteRunners.removeValue(forKey: session.id)

        if session.state != .stopped {
            if session.state != .stopping {
                try? session.transitionTo(.stopping)
            }
            try? session.transitionTo(.stopped)
        }

        // Auto-remove the session from the sidebar
        sessionManager.removeSession(session)
        if selectedSessionId == session.id {
            selectedSessionId = nil
        }
    }

    // MARK: - Private

    private func handleAction(_ action: String, sessionId: String) {
        guard let session = sessionManager.session(byId: sessionId) else { return }
        switch action {
        case "start": startSession(session)
        case "stop": stopSession(session)
        case "restart": restartSession(session)
        case "remove": removeSession(session)
        default: break
        }
    }

    private func reloadBlueprints() {
        do {
            try sessionManager.loadBlueprints()
        } catch {
            print("Failed to reload blueprints: \(error)")
        }
    }
}
