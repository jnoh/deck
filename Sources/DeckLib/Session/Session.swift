import Foundation
import Observation

// MARK: - Session State

public enum SessionState: String, Sendable, CaseIterable {
    case stopped
    case provisioning
    case starting
    case running
    case degraded
    case stopping
    case deprovisioning

    public var isTransitional: Bool {
        switch self {
        case .provisioning, .starting, .stopping, .deprovisioning:
            return true
        default:
            return false
        }
    }

    public var isActive: Bool {
        switch self {
        case .running, .degraded:
            return true
        default:
            return false
        }
    }

    func validNextStates(isLocal: Bool) -> Set<SessionState> {
        switch self {
        case .stopped:
            return isLocal ? [.starting] : [.provisioning, .starting]
        case .provisioning:
            return [.starting, .stopped]
        case .starting:
            return [.running, .stopped]
        case .running:
            return [.degraded, .stopping]
        case .degraded:
            return [.running, .stopping]
        case .stopping:
            return isLocal ? [.stopped] : [.deprovisioning, .stopped]
        case .deprovisioning:
            return [.stopped]
        }
    }
}

public enum SessionTransitionError: Error, CustomStringConvertible {
    case invalidTransition(from: SessionState, to: SessionState)

    public var description: String {
        switch self {
        case .invalidTransition(let from, let to):
            return "Invalid state transition: \(from.rawValue) → \(to.rawValue)"
        }
    }
}

// MARK: - Session (an instance of a blueprint)

@Observable
public final class Session: Identifiable, @unchecked Sendable {
    public let id: String
    public let instanceNumber: Int
    public let config: SessionConfig
    public private(set) var state: SessionState = .stopped
    public var displayName: String
    public let status = SessionStatus()

    public init(config: SessionConfig, instanceNumber: Int = 1) {
        self.id = "\(config.name)-\(UUID().uuidString.prefix(8))"
        self.instanceNumber = instanceNumber
        self.config = config
        self.displayName = instanceNumber == 1
            ? config.name
            : "\(config.name) (\(instanceNumber))"
    }

    public func transitionTo(_ newState: SessionState) throws {
        let valid = state.validNextStates(isLocal: config.type == .local)
        guard valid.contains(newState) else {
            throw SessionTransitionError.invalidTransition(from: state, to: newState)
        }
        state = newState
    }

    /// Force state without validation — for internal use (e.g., error recovery)
    func forceState(_ newState: SessionState) {
        state = newState
    }
}

// MARK: - Session Manager

@Observable
public final class SessionManager: @unchecked Sendable {
    /// Blueprints loaded from TOML files
    public private(set) var blueprints: [SessionConfig] = []
    /// Live session instances
    public private(set) var sessions: [Session] = []

    public init() {}

    public func loadBlueprints(from directory: URL = ConfigLoader.defaultConfigDirectory) throws {
        blueprints = try ConfigLoader.loadAll(from: directory)
    }

    /// Create a new session instance from a blueprint
    public func createInstance(from blueprint: SessionConfig) -> Session {
        let existing = sessions.filter { $0.config.name == blueprint.name }
        let instanceNumber = (existing.map(\.instanceNumber).max() ?? 0) + 1
        let session = Session(config: blueprint, instanceNumber: instanceNumber)
        sessions.append(session)
        return session
    }

    /// Remove a stopped session instance
    public func removeSession(_ session: Session) {
        guard session.state == .stopped else { return }
        sessions.removeAll { $0.id == session.id }
    }

    public func session(byId id: String) -> Session? {
        sessions.first { $0.id == id }
    }

    public func blueprint(named name: String) -> SessionConfig? {
        blueprints.first { $0.name == name }
    }

    // MARK: - Grouped accessors

    public var runningSessions: [Session] {
        sessions.filter { $0.state == .running }.sorted { $0.displayName < $1.displayName }
    }

    public var degradedSessions: [Session] {
        sessions.filter { $0.state == .degraded }.sorted { $0.displayName < $1.displayName }
    }

    public var startingSessions: [Session] {
        sessions.filter { $0.state.isTransitional }.sorted { $0.displayName < $1.displayName }
    }

    public var stoppedSessions: [Session] {
        sessions.filter { $0.state == .stopped }.sorted { $0.displayName < $1.displayName }
    }
}
