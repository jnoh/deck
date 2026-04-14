import Foundation

public final class ReconnectionManager: @unchecked Sendable {
    private let healthMonitor: HealthMonitor
    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private var retryCounts: [String: Int] = [:]
    private let lock = NSLock()

    public init(healthMonitor: HealthMonitor, maxRetries: Int = 5, baseDelay: TimeInterval = 2.0) {
        self.healthMonitor = healthMonitor
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }

    /// Attempt to reconnect a remote session after an unexpected SSH drop.
    /// Returns true if reconnection succeeded, false if the session should be degraded.
    public func handleSSHDrop(
        session: Session,
        runner: RemoteSessionRunner,
        healthCommand: String
    ) async -> Bool {
        guard !runner.isIntentionalStop else { return false }

        // Check if remote is still healthy
        let healthy = await runHealthCheck(command: healthCommand)
        if !healthy {
            try? session.transitionTo(.degraded)
            resetRetryCount(for: session.config.name)
            return false
        }

        // Attempt reconnection with exponential backoff
        let retryCount = getRetryCount(for: session.config.name)
        guard retryCount < maxRetries else {
            try? session.transitionTo(.degraded)
            resetRetryCount(for: session.config.name)
            return false
        }

        incrementRetryCount(for: session.config.name)

        let delay = baseDelay * pow(2.0, Double(retryCount))
        try? await Task.sleep(for: .seconds(delay))

        do {
            try await runner.reconnect()
            resetRetryCount(for: session.config.name)
            return true
        } catch {
            return await handleSSHDrop(session: session, runner: runner, healthCommand: healthCommand)
        }
    }

    public func resetRetryCount(for name: String) {
        lock.lock()
        retryCounts.removeValue(forKey: name)
        lock.unlock()
    }

    private func getRetryCount(for name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return retryCounts[name] ?? 0
    }

    private func incrementRetryCount(for name: String) {
        lock.lock()
        retryCounts[name] = (retryCounts[name] ?? 0) + 1
        lock.unlock()
    }

    private func runHealthCheck(command: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
