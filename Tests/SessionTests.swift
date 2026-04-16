import Testing
import Foundation
@testable import DeckLib

@Suite("Session State Machine")
struct SessionStateTests {

    private func makeLocalSession(name: String = "test") -> Session {
        let config = try! SessionConfig.parse(from: """
        [session]
        name = "\(name)"
        type = "local"
        """)
        return Session(config: config)
    }

    private func makeRemoteSession(name: String = "remote-test") -> Session {
        let config = try! SessionConfig.parse(from: """
        [session]
        name = "\(name)"
        type = "remote"

        [host]
        ssh = "ssh user@host"
        """)
        return Session(config: config)
    }

    // MARK: - Initial state

    @Test func initialStateIsStopped() {
        let session = makeLocalSession()
        #expect(session.state == .stopped)
    }

    // MARK: - Valid local transitions

    @Test func localStartupFlow() throws {
        let session = makeLocalSession()

        try session.transitionTo(.starting)
        #expect(session.state == .starting)

        try session.transitionTo(.running)
        #expect(session.state == .running)
    }

    @Test func localShutdownFlow() throws {
        let session = makeLocalSession()

        try session.transitionTo(.starting)
        try session.transitionTo(.running)
        try session.transitionTo(.stopping)
        #expect(session.state == .stopping)

        try session.transitionTo(.stopped)
        #expect(session.state == .stopped)
    }

    @Test func localDegradedFlow() throws {
        let session = makeLocalSession()

        try session.transitionTo(.starting)
        try session.transitionTo(.running)
        try session.transitionTo(.degraded)
        #expect(session.state == .degraded)

        // Can recover back to running
        try session.transitionTo(.running)
        #expect(session.state == .running)
    }

    @Test func localDegradedCanStop() throws {
        let session = makeLocalSession()

        try session.transitionTo(.starting)
        try session.transitionTo(.running)
        try session.transitionTo(.degraded)
        try session.transitionTo(.stopping)
        #expect(session.state == .stopping)
    }

    // MARK: - Valid remote transitions

    @Test func remoteFullLifecycle() throws {
        let session = makeRemoteSession()

        try session.transitionTo(.provisioning)
        try session.transitionTo(.starting)
        try session.transitionTo(.running)
        try session.transitionTo(.stopping)
        try session.transitionTo(.deprovisioning)
        try session.transitionTo(.stopped)
        #expect(session.state == .stopped)
    }

    @Test func remoteCanSkipProvisioning() throws {
        let session = makeRemoteSession()
        try session.transitionTo(.starting)
        #expect(session.state == .starting)
    }

    @Test func remoteStopCanSkipDeprovisioning() throws {
        let session = makeRemoteSession()
        try session.transitionTo(.starting)
        try session.transitionTo(.running)
        try session.transitionTo(.stopping)
        try session.transitionTo(.stopped)
        #expect(session.state == .stopped)
    }

    // MARK: - Invalid transitions

    @Test func cannotSkipStarting() {
        let session = makeLocalSession()

        #expect(throws: SessionTransitionError.self) {
            try session.transitionTo(.running)
        }
    }

    @Test func localCannotProvision() {
        let session = makeLocalSession()

        #expect(throws: SessionTransitionError.self) {
            try session.transitionTo(.provisioning)
        }
    }

    @Test func localCannotDeprovision() throws {
        let session = makeLocalSession()
        try session.transitionTo(.starting)
        try session.transitionTo(.running)
        try session.transitionTo(.stopping)

        #expect(throws: SessionTransitionError.self) {
            try session.transitionTo(.deprovisioning)
        }
    }

    @Test func cannotGoFromStoppedToStopping() {
        let session = makeLocalSession()

        #expect(throws: SessionTransitionError.self) {
            try session.transitionTo(.stopping)
        }
    }

    // MARK: - State properties

    @Test func transitionalStates() {
        #expect(SessionState.provisioning.isTransitional)
        #expect(SessionState.starting.isTransitional)
        #expect(SessionState.stopping.isTransitional)
        #expect(SessionState.deprovisioning.isTransitional)

        #expect(!SessionState.stopped.isTransitional)
        #expect(!SessionState.running.isTransitional)
        #expect(!SessionState.degraded.isTransitional)
    }

    @Test func activeStates() {
        #expect(SessionState.running.isActive)
        #expect(SessionState.degraded.isActive)

        #expect(!SessionState.stopped.isActive)
        #expect(!SessionState.starting.isActive)
        #expect(!SessionState.stopping.isActive)
    }

    // MARK: - Display name

    @Test func displayNameFirstInstance() {
        let session = makeLocalSession(name: "my-session")
        #expect(session.displayName == "my-session")
    }

    @Test func displayNameSubsequentInstance() {
        let config = try! SessionConfig.parse(from: """
        [session]
        name = "my-session"
        type = "local"
        """)
        let session = Session(config: config, instanceNumber: 3)
        #expect(session.displayName == "my-session (3)")
    }
}

@Suite("Session Manager")
struct SessionManagerTests {

    @Test func loadsBlueprintsFromDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-mgr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let betaDir = tmpDir.appendingPathComponent("beta.deck")
        try FileManager.default.createDirectory(at: betaDir, withIntermediateDirectories: true)
        try """
        [session]
        name = "beta"
        type = "local"
        """.write(to: betaDir.appendingPathComponent("session.toml"), atomically: true, encoding: .utf8)

        let alphaDir = tmpDir.appendingPathComponent("alpha.deck")
        try FileManager.default.createDirectory(at: alphaDir, withIntermediateDirectories: true)
        try """
        [session]
        name = "alpha"
        type = "local"
        """.write(to: alphaDir.appendingPathComponent("session.toml"), atomically: true, encoding: .utf8)

        let manager = SessionManager()
        try manager.loadBlueprints(from: tmpDir)

        #expect(manager.blueprints.count == 2)
        #expect(manager.blueprints[0].name == "alpha")
        #expect(manager.blueprints[1].name == "beta")
        #expect(manager.sessions.isEmpty)
    }

    @Test func createsInstanceFromBlueprint() throws {
        let config = try SessionConfig.parse(from: """
        [session]
        name = "test"
        type = "local"
        """)

        let manager = SessionManager()
        let session = manager.createInstance(from: config)

        #expect(manager.sessions.count == 1)
        #expect(session.config.name == "test")
        #expect(session.instanceNumber == 1)
        #expect(session.displayName == "test")
    }

    @Test func createsMultipleInstancesFromSameBlueprint() throws {
        let config = try SessionConfig.parse(from: """
        [session]
        name = "test"
        type = "local"
        """)

        let manager = SessionManager()
        let s1 = manager.createInstance(from: config)
        let s2 = manager.createInstance(from: config)
        let s3 = manager.createInstance(from: config)

        #expect(manager.sessions.count == 3)
        #expect(s1.instanceNumber == 1)
        #expect(s2.instanceNumber == 2)
        #expect(s3.instanceNumber == 3)
        #expect(s1.id != s2.id)
        #expect(s2.id != s3.id)
        #expect(s2.displayName == "test (2)")
    }

    @Test func removesStoppedSession() throws {
        let config = try SessionConfig.parse(from: """
        [session]
        name = "test"
        type = "local"
        """)

        let manager = SessionManager()
        let session = manager.createInstance(from: config)

        #expect(manager.sessions.count == 1)
        manager.removeSession(session)
        #expect(manager.sessions.isEmpty)
    }

    @Test func cannotRemoveRunningSession() throws {
        let config = try SessionConfig.parse(from: """
        [session]
        name = "test"
        type = "local"
        """)

        let manager = SessionManager()
        let session = manager.createInstance(from: config)
        try session.transitionTo(.starting)
        try session.transitionTo(.running)

        manager.removeSession(session)
        #expect(manager.sessions.count == 1)
    }

    @Test func groupsSessionsByState() throws {
        let config = try SessionConfig.parse(from: """
        [session]
        name = "test"
        type = "local"
        """)

        let manager = SessionManager()
        let s1 = manager.createInstance(from: config)
        let _ = manager.createInstance(from: config)
        let _ = manager.createInstance(from: config)

        #expect(manager.stoppedSessions.count == 3)
        #expect(manager.runningSessions.isEmpty)

        try s1.transitionTo(.starting)
        try s1.transitionTo(.running)

        #expect(manager.runningSessions.count == 1)
        #expect(manager.stoppedSessions.count == 2)
    }

    @Test func findsBlueprintByName() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-mgr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let targetDir = tmpDir.appendingPathComponent("target.deck")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try """
        [session]
        name = "target"
        type = "local"
        """.write(to: targetDir.appendingPathComponent("session.toml"), atomically: true, encoding: .utf8)

        let manager = SessionManager()
        try manager.loadBlueprints(from: tmpDir)

        #expect(manager.blueprint(named: "target") != nil)
        #expect(manager.blueprint(named: "nonexistent") == nil)
    }
}
