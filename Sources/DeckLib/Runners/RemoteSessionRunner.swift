import Foundation

public final class RemoteSessionRunner: @unchecked Sendable {
    public let session: Session
    public weak var delegate: SessionRunnerDelegate?

    private var sshProcess: Process?
    private var scriptPath: String?
    private let queue = DispatchQueue(label: "deck.remote-session", qos: .userInitiated)
    private var intentionalStop = false

    public var isRunning: Bool {
        sshProcess?.isRunning ?? false
    }

    public init(session: Session) {
        self.session = session
    }

    // MARK: - Start

    public func start() async throws {
        guard session.state == .stopped else {
            throw SessionRunnerError.invalidState("Cannot start: session is \(session.state.rawValue)")
        }

        let config = session.config
        guard let hostConfig = config.host, let sshCommand = hostConfig.ssh else {
            throw SessionRunnerError.invalidState("Remote session requires host.ssh configuration")
        }

        // Provisioning
        if let provision = hostConfig.provision {
            try session.transitionTo(.provisioning)
            let success = await runLocalCommand(provision)
            if !success {
                try session.transitionTo(.stopped)
                throw SessionRunnerError.invalidState("Provisioning failed")
            }
        }

        // Ready check polling
        if let readyCheck = hostConfig.readyCheck {
            if session.state == .stopped {
                try session.transitionTo(.provisioning)
            }
            let timeout = hostConfig.readyTimeoutSeconds
            let ready = await pollReadyCheck(command: readyCheck, timeout: timeout)
            if !ready {
                try session.transitionTo(.stopped)
                throw SessionRunnerError.invalidState("Ready check timed out after \(timeout)s")
            }
        }

        if session.state != .starting {
            try session.transitionTo(.starting)
        }

        // Pipe startup script to remote
        let script = composeScript(steps: config.startup.steps)
        let remotePath = "/tmp/deck-\(config.name).sh"
        let _ = await runLocalCommand(
            "echo \(shellEscape(script)) | \(sshCommand) -- bash -c 'cat > \(remotePath) && chmod +x \(remotePath)'"
        )

        // Create remote tmux session
        let workingDir = config.startup.workingDir
        let tmuxSessionName = "deck-\(config.name)"
        let tmuxCmd = "\(sshCommand) -- tmux new-session -d -s \(shellEscape(tmuxSessionName)) 'cd \(shellEscape(workingDir)) && bash \(remotePath)'"
        let _ = await runLocalCommand(tmuxCmd)

        // Start SSH attach process
        let attachCmd = "\(sshCommand) -- tmux attach -t \(shellEscape(tmuxSessionName))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", attachCmd]
        process.terminationHandler = { [weak self] proc in
            self?.handleProcessTerminated(exitCode: proc.terminationStatus)
        }

        try process.run()
        self.sshProcess = process

        try session.transitionTo(.running)
        delegate?.sessionDidStart(session)
    }

    // MARK: - Stop

    public func stop() async {
        guard session.state == .running || session.state == .degraded else { return }
        intentionalStop = true

        try? session.transitionTo(.stopping)

        let config = session.config
        let hostConfig = config.host

        // Run teardown commands via SSH
        if let sshCommand = hostConfig?.ssh {
            let tmuxSessionName = "deck-\(config.name)"

            for step in config.teardown.steps {
                let _ = await runLocalCommand(
                    "\(sshCommand) -- tmux send-keys -t \(shellEscape(tmuxSessionName)) \(shellEscape(step)) Enter"
                )
            }

            let _ = await runLocalCommand(
                "\(sshCommand) -- tmux kill-session -t \(shellEscape(tmuxSessionName))"
            )
        }

        sshProcess?.terminate()
        sshProcess = nil

        // Deprovisioning
        if let deprovision = hostConfig?.deprovision {
            try? session.transitionTo(.deprovisioning)
            let _ = await runLocalCommand(deprovision)
        }

        if session.state != .stopped {
            session.forceState(.stopped)
        }

        delegate?.sessionDidStop(session, exitCode: nil)
    }

    // MARK: - Reconnection support

    public var isIntentionalStop: Bool {
        intentionalStop
    }

    public func reconnect() async throws {
        guard let hostConfig = session.config.host, let sshCommand = hostConfig.ssh else { return }

        let tmuxSessionName = "deck-\(session.config.name)"
        let attachCmd = "\(sshCommand) -- tmux attach -t \(shellEscape(tmuxSessionName))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", attachCmd]
        process.terminationHandler = { [weak self] proc in
            self?.handleProcessTerminated(exitCode: proc.terminationStatus)
        }

        try process.run()
        self.sshProcess = process
    }

    // MARK: - Process callbacks

    private func handleProcessTerminated(exitCode: Int32) {
        if !intentionalStop {
            delegate?.sessionDidStop(session, exitCode: exitCode)
        }
    }

    // MARK: - Private

    private func runLocalCommand(_ command: String) async -> Bool {
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

    private func pollReadyCheck(command: String, timeout: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            if await runLocalCommand(command) {
                return true
            }
            try? await Task.sleep(for: .seconds(2))
        }
        return false
    }

    private func composeScript(steps: [String]) -> String {
        if steps.isEmpty {
            return "exec bash -l"
        }
        return steps.joined(separator: "\n")
    }

    private func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
