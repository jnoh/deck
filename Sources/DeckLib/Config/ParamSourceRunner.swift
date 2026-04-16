import Foundation

// MARK: - Param Option (value + label from source command)

public struct ParamOption: Sendable, Identifiable {
    public let value: String
    public let label: String
    public var id: String { value }
}

// MARK: - Param Source Error

public enum ParamSourceError: Error, CustomStringConvertible {
    case timeout(seconds: Int)
    case commandFailed(exitCode: Int32, stderr: String)
    case invalidJSON(String)

    public var description: String {
        switch self {
        case .timeout(let seconds):
            return "Command timed out after \(seconds)s"
        case .commandFailed(let code, let stderr):
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Command failed (exit \(code))\(msg.isEmpty ? "" : ": \(msg)")"
        case .invalidJSON(let detail):
            return "Invalid JSON output: \(detail)"
        }
    }
}

// MARK: - Runner

public struct ParamSourceRunner {
    public static let defaultTimeout: Int = 15

    /// Run a source command and parse its JSON output into options.
    ///
    /// - Parameters:
    ///   - command: Shell command string to execute
    ///   - packageDir: The .deck package directory (used as working dir and DECK_PACKAGE_DIR)
    ///   - environment: Additional env vars (e.g., already-filled upstream params)
    ///   - timeout: Max seconds to wait
    /// - Returns: Array of ParamOption
    public static func run(
        command: String,
        packageDir: URL?,
        environment: [String: String] = [:],
        timeout: Int = defaultTimeout
    ) async throws -> [ParamOption] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        if let dir = packageDir {
            process.currentDirectoryURL = dir
        }

        // Build environment
        var env = ProcessInfo.processInfo.environment
        if let dir = packageDir {
            env["DECK_PACKAGE_DIR"] = dir.path
        }
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Timeout handling
        let pid = process.processIdentifier
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            kill(pid, SIGTERM)
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        // Check if we were killed by timeout
        if process.terminationStatus == 15 || (process.terminationStatus != 0 && timeoutTask.isCancelled == false) {
            // Heuristic: if SIGTERM, likely timeout
            if process.terminationReason == .uncaughtSignal {
                throw ParamSourceError.timeout(seconds: timeout)
            }
        }

        guard process.terminationStatus == 0 else {
            throw ParamSourceError.commandFailed(exitCode: process.terminationStatus, stderr: stderrString)
        }

        return try parseOptions(from: stdoutString)
    }

    static func parseOptions(from jsonString: String) throws -> [ParamOption] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParamSourceError.invalidJSON("empty output")
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw ParamSourceError.invalidJSON("not valid UTF-8")
        }

        let decoded: Any
        do {
            decoded = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ParamSourceError.invalidJSON(error.localizedDescription)
        }

        guard let array = decoded as? [[String: Any]] else {
            throw ParamSourceError.invalidJSON("expected array of {value, label} objects")
        }

        return array.compactMap { dict in
            guard let value = dict["value"] as? String,
                  let label = dict["label"] as? String else { return nil }
            return ParamOption(value: value, label: label)
        }
    }
}
