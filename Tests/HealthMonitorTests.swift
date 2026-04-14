import Testing
import Foundation
@testable import DeckLib

@Suite("Health Monitor")
struct HealthMonitorTests {

    private func makeRunningSession(
        name: String = "health-test",
        command: String = "true",
        interval: Int = 1
    ) throws -> Session {
        let toml = """
        [session]
        name = "\(name)"
        type = "local"

        [health]
        command = "\(command)"
        interval_seconds = \(interval)
        """
        let session = Session(config: try SessionConfig.parse(from: toml))
        try session.transitionTo(.starting)
        try session.transitionTo(.running)
        return session
    }

    @Test func healthySessionStaysRunning() async throws {
        let session = try makeRunningSession(command: "true", interval: 1)
        let monitor = HealthMonitor()

        monitor.startMonitoring(session)
        try await Task.sleep(for: .seconds(3))

        #expect(session.state == .running)
        monitor.stopAll()
    }

    @Test func unhealthySessionBecomesDegraded() async throws {
        let session = try makeRunningSession(command: "false", interval: 1)
        let monitor = HealthMonitor()

        monitor.startMonitoring(session)
        try await Task.sleep(for: .seconds(3))

        #expect(session.state == .degraded)
        monitor.stopAll()
    }

    @Test func degradedSessionRecovers() async throws {
        // Start with a command that fails, then swap to one that succeeds
        let tmpFile = NSTemporaryDirectory() + "deck-health-\(UUID().uuidString)"
        // Command: fail if file exists, succeed if not
        let session = try makeRunningSession(
            name: "recovery-test",
            command: "test ! -f \(tmpFile)",
            interval: 1
        )

        // Create the file so health check fails
        FileManager.default.createFile(atPath: tmpFile, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let monitor = HealthMonitor()
        monitor.startMonitoring(session)

        try await Task.sleep(for: .seconds(3))
        #expect(session.state == .degraded)

        // Remove the file so health check passes
        try FileManager.default.removeItem(atPath: tmpFile)

        try await Task.sleep(for: .seconds(3))
        #expect(session.state == .running)

        monitor.stopAll()
    }

    @Test func stopMonitoringCancelsPolling() async throws {
        let session = try makeRunningSession(command: "false", interval: 1)
        let monitor = HealthMonitor()

        monitor.startMonitoring(session)
        monitor.stopMonitoring(name: session.id)

        try await Task.sleep(for: .seconds(3))

        // Should still be running since monitoring was stopped before the check ran
        #expect(session.state == .running)
    }

    @Test func defaultHealthCommandAlwaysPasses() async throws {
        let toml = """
        [session]
        name = "default-health"
        type = "local"
        """
        let session = Session(config: try SessionConfig.parse(from: toml))
        try session.transitionTo(.starting)
        try session.transitionTo(.running)

        #expect(session.config.health.command == "true")

        let monitor = HealthMonitor()
        monitor.startMonitoring(session)
        try await Task.sleep(for: .seconds(3))

        #expect(session.state == .running)
        monitor.stopAll()
    }
}
