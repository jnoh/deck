import Foundation

public final class HealthMonitor: @unchecked Sendable {
    private var tasks: [String: Task<Void, Never>] = [:]
    private let lock = NSLock()

    public init() {}

    deinit {
        stopAll()
    }

    public func startMonitoring(_ session: Session) {
        let name = session.id
        stopMonitoring(name: name)

        let interval = session.config.health.intervalSeconds
        let command = session.config.health.command

        let task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                guard session.state == .running || session.state == .degraded else { break }

                let healthy = await self?.runHealthCheck(command: command, timeout: TimeInterval(interval)) ?? false

                guard !Task.isCancelled else { break }

                if healthy && session.state == .degraded {
                    try? session.transitionTo(.running)
                } else if !healthy && session.state == .running {
                    try? session.transitionTo(.degraded)
                }
            }
        }

        lock.lock()
        tasks[name] = task
        lock.unlock()
    }

    public func stopMonitoring(name: String) {
        lock.lock()
        let task = tasks.removeValue(forKey: name)
        lock.unlock()
        task?.cancel()
    }

    public func stopAll() {
        lock.lock()
        let allTasks = tasks
        tasks.removeAll()
        lock.unlock()
        for (_, task) in allTasks {
            task.cancel()
        }
    }

    private func runHealthCheck(command: String, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }

            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWork
            )

            do {
                try process.run()
                process.waitUntilExit()
                timeoutWork.cancel()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                timeoutWork.cancel()
                continuation.resume(returning: false)
            }
        }
    }
}
