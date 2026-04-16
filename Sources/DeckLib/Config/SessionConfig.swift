import Foundation
import TOMLKit

// MARK: - Session Type

public enum SessionType: String, Codable, Sendable {
    case local
    case remote
}

// MARK: - Config Error

public enum ConfigError: Error, CustomStringConvertible {
    case missingRequiredField(String)
    case invalidSessionType(String)
    case parseError(file: String, underlying: Error)

    public var description: String {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidSessionType(let value):
            return "Invalid session type '\(value)'. Must be 'local' or 'remote'."
        case .parseError(let file, let underlying):
            return "Failed to parse '\(file)': \(underlying)"
        }
    }
}

// MARK: - Config Models

public struct HostConfig: Codable, Sendable {
    public var provision: String?
    public var ssh: String?
    public var deprovision: String?
    public var readyCheck: String?
    public var readyTimeoutSeconds: Int

    enum CodingKeys: String, CodingKey {
        case provision
        case ssh
        case deprovision
        case readyCheck = "ready_check"
        case readyTimeoutSeconds = "ready_timeout_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provision = try container.decodeIfPresent(String.self, forKey: .provision)
        ssh = try container.decodeIfPresent(String.self, forKey: .ssh)
        deprovision = try container.decodeIfPresent(String.self, forKey: .deprovision)
        readyCheck = try container.decodeIfPresent(String.self, forKey: .readyCheck)
        readyTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .readyTimeoutSeconds) ?? 120
    }

    public init(
        provision: String? = nil,
        ssh: String? = nil,
        deprovision: String? = nil,
        readyCheck: String? = nil,
        readyTimeoutSeconds: Int = 120
    ) {
        self.provision = provision
        self.ssh = ssh
        self.deprovision = deprovision
        self.readyCheck = readyCheck
        self.readyTimeoutSeconds = readyTimeoutSeconds
    }
}

public struct StartupConfig: Codable, Sendable {
    public var workingDir: String
    public var steps: [String]

    enum CodingKeys: String, CodingKey {
        case workingDir = "working_dir"
        case steps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawDir = try container.decodeIfPresent(String.self, forKey: .workingDir) ?? "~"
        workingDir = Self.expandTilde(rawDir)
        steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
    }

    public init(workingDir: String = "~", steps: [String] = []) {
        self.workingDir = Self.expandTilde(workingDir)
        self.steps = steps
    }

    static func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") || path == "~" {
            return NSString(string: path).expandingTildeInPath
        }
        return path
    }
}

public struct TeardownConfig: Codable, Sendable {
    public var steps: [String]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
    }

    public init(steps: [String] = []) {
        self.steps = steps
    }
}

public struct HealthConfig: Codable, Sendable {
    public var command: String
    public var intervalSeconds: Int

    enum CodingKeys: String, CodingKey {
        case command
        case intervalSeconds = "interval_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? "true"
        intervalSeconds = try container.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 10
    }

    public init(command: String = "true", intervalSeconds: Int = 10) {
        self.command = command
        self.intervalSeconds = intervalSeconds
    }
}

// MARK: - Session Section (nested under [session] in TOML)

private struct SessionSection: Codable {
    let name: String
    let type: String
    var icon: String?
    var description: String?
}

// MARK: - Session Parameter (user-configurable form field)

public struct SessionParam: Codable, Sendable {
    public let key: String
    public let label: String
    public var placeholder: String?
    public var `default`: String?
    public var required: Bool?
    public var type: String?      // "text" (default) | "select"
    public var source: String?    // shell command → JSON array of {value, label}

    public var isSelect: Bool { type == "select" }
    public var isRequired: Bool { `required` ?? false }
    public var defaultValue: String { `default` ?? "" }
}

// MARK: - Raw TOML structure for decoding

private struct RawSessionConfig: Codable {
    let session: SessionSection
    var host: HostConfig?
    var startup: StartupConfig?
    var teardown: TeardownConfig?
    var health: HealthConfig?
    var params: [SessionParam]?
}

// MARK: - SessionConfig

public struct SessionConfig: Sendable {
    public let name: String
    public let type: SessionType
    public let icon: String
    public let description: String
    public let host: HostConfig?
    public let startup: StartupConfig
    public let teardown: TeardownConfig
    public let health: HealthConfig
    public let params: [SessionParam]
    public var filePath: URL?
    public var packageDir: URL?
    public var paramValues: [String: String] = [:]

    /// Effective working directory
    public var effectiveWorkingDir: String {
        startup.workingDir
    }

    /// Whether this config was loaded from a .deck package
    public var isPackage: Bool { packageDir != nil }

    /// Path to start.sh inside the package, if it exists
    public var startScript: URL? {
        guard let dir = packageDir else { return nil }
        let path = dir.appendingPathComponent("start.sh")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Path to stop.sh inside the package, if it exists
    public var stopScript: URL? {
        guard let dir = packageDir else { return nil }
        let path = dir.appendingPathComponent("stop.sh")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Path to health.sh inside the package, if it exists
    public var healthScript: URL? {
        guard let dir = packageDir else { return nil }
        let path = dir.appendingPathComponent("health.sh")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    public static func parse(from tomlString: String, filePath: URL? = nil) throws -> SessionConfig {
        let raw: RawSessionConfig
        do {
            raw = try TOMLDecoder().decode(RawSessionConfig.self, from: tomlString)
        } catch {
            throw ConfigError.parseError(
                file: filePath?.lastPathComponent ?? "<unknown>",
                underlying: error
            )
        }

        guard let sessionType = SessionType(rawValue: raw.session.type) else {
            throw ConfigError.invalidSessionType(raw.session.type)
        }

        return SessionConfig(
            name: raw.session.name,
            type: sessionType,
            icon: raw.session.icon ?? "▸",
            description: raw.session.description ?? "",
            host: raw.host,
            startup: raw.startup ?? StartupConfig(),
            teardown: raw.teardown ?? TeardownConfig(),
            health: raw.health ?? HealthConfig(),
            params: raw.params ?? [],
            filePath: filePath
        )
    }
}
