import Testing
import Foundation
@testable import DeckLib

@Suite("Reconnection Manager")
struct ReconnectionManagerTests {

    private func makeRunningRemoteSession(name: String = "reconnect-test") throws -> Session {
        let toml = """
        [session]
        name = "\(name)"
        type = "remote"

        [host]
        ssh = "ssh user@host"

        [health]
        command = "true"
        interval_seconds = 5
        """
        let session = Session(config: try SessionConfig.parse(from: toml))
        try session.transitionTo(.starting)
        try session.transitionTo(.running)
        return session
    }

    @Test func unhealthyRemoteTransitionsToDegraded() async throws {
        let session = try makeRunningRemoteSession(name: "unhealthy-remote")
        let monitor = HealthMonitor()
        let manager = ReconnectionManager(healthMonitor: monitor, maxRetries: 3, baseDelay: 0.1)

        let runner = RemoteSessionRunner(session: session)

        // Health check fails → should degrade
        let reconnected = await manager.handleSSHDrop(
            session: session,
            runner: runner,
            healthCommand: "false"
        )

        #expect(!reconnected)
        #expect(session.state == .degraded)
    }

    @Test func retryCountResets() {
        let monitor = HealthMonitor()
        let manager = ReconnectionManager(healthMonitor: monitor)
        manager.resetRetryCount(for: "test")
        // Just verify no crash — internal state is private
    }

    @Test func maxRetriesExhausted() async throws {
        let session = try makeRunningRemoteSession(name: "max-retry")
        let monitor = HealthMonitor()
        // Set maxRetries to 0 so it immediately gives up
        let manager = ReconnectionManager(healthMonitor: monitor, maxRetries: 0, baseDelay: 0.1)

        let runner = RemoteSessionRunner(session: session)

        // Health check passes but maxRetries is 0
        let reconnected = await manager.handleSSHDrop(
            session: session,
            runner: runner,
            healthCommand: "true"
        )

        #expect(!reconnected)
        #expect(session.state == .degraded)
    }
}
