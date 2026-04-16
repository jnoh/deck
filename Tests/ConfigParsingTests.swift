import Testing
import Foundation
@testable import DeckLib

@Suite("Config Parsing")
struct ConfigParsingTests {

    // MARK: - Local session parsing

    @Test func parsesLocalSession() throws {
        let toml = """
        [session]
        name = "claude-code"
        type = "local"
        icon = "🤖"
        description = "Claude Code on local project"

        [startup]
        working_dir = "/tmp/test"
        steps = ["claude"]

        [teardown]
        steps = []

        [health]
        command = "pgrep -f claude"
        interval_seconds = 10
        """

        let config = try SessionConfig.parse(from: toml)

        #expect(config.name == "claude-code")
        #expect(config.type == .local)
        #expect(config.icon == "🤖")
        #expect(config.description == "Claude Code on local project")
        #expect(config.startup.workingDir == "/tmp/test")
        #expect(config.startup.steps == ["claude"])
        #expect(config.teardown.steps.isEmpty)
        #expect(config.health.command == "pgrep -f claude")
        #expect(config.health.intervalSeconds == 10)
        #expect(config.host == nil)
    }

    // MARK: - Remote session parsing

    @Test func parsesRemoteSession() throws {
        let toml = """
        [session]
        name = "remote-claude"
        type = "remote"
        icon = "🌐"
        description = "Remote workspace"

        [host]
        provision = "coder create ws --yes"
        ssh = "coder ssh ws"
        deprovision = "coder stop ws --yes"
        ready_check = "coder ssh ws -- echo ok"
        ready_timeout_seconds = 300

        [startup]
        working_dir = "/workspace/app"
        steps = ["claude"]

        [health]
        command = "coder list | grep running"
        interval_seconds = 30
        """

        let config = try SessionConfig.parse(from: toml)

        #expect(config.name == "remote-claude")
        #expect(config.type == .remote)
        #expect(config.host != nil)
        #expect(config.host?.provision == "coder create ws --yes")
        #expect(config.host?.ssh == "coder ssh ws")
        #expect(config.host?.deprovision == "coder stop ws --yes")
        #expect(config.host?.readyCheck == "coder ssh ws -- echo ok")
        #expect(config.host?.readyTimeoutSeconds == 300)
        #expect(config.health.intervalSeconds == 30)
    }

    // MARK: - Defaults

    @Test func appliesDefaults() throws {
        let toml = """
        [session]
        name = "minimal"
        type = "local"
        """

        let config = try SessionConfig.parse(from: toml)

        #expect(config.icon == "▸")
        #expect(config.description == "")
        #expect(config.health.command == "true")
        #expect(config.health.intervalSeconds == 10)
        #expect(config.startup.steps.isEmpty)
        #expect(config.teardown.steps.isEmpty)
    }

    @Test func appliesHostDefaults() throws {
        let toml = """
        [session]
        name = "remote-min"
        type = "remote"

        [host]
        ssh = "ssh user@host"
        """

        let config = try SessionConfig.parse(from: toml)

        #expect(config.host?.readyTimeoutSeconds == 120)
        #expect(config.host?.provision == nil)
        #expect(config.host?.deprovision == nil)
        #expect(config.host?.readyCheck == nil)
    }

    // MARK: - Tilde expansion

    @Test func expandsTildeInWorkingDir() throws {
        let toml = """
        [session]
        name = "tilde-test"
        type = "local"

        [startup]
        working_dir = "~/projects/app"
        """

        let config = try SessionConfig.parse(from: toml)
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        #expect(config.startup.workingDir == "\(home)/projects/app")
        #expect(!config.startup.workingDir.contains("~"))
    }

    // MARK: - Error cases

    @Test func rejectsInvalidSessionType() throws {
        let toml = """
        [session]
        name = "bad"
        type = "container"
        """

        #expect(throws: ConfigError.self) {
            try SessionConfig.parse(from: toml)
        }
    }

    @Test func rejectsMissingName() throws {
        let toml = """
        [session]
        type = "local"
        """

        #expect(throws: (any Error).self) {
            try SessionConfig.parse(from: toml)
        }
    }

    @Test func rejectsMissingType() throws {
        let toml = """
        [session]
        name = "no-type"
        """

        #expect(throws: (any Error).self) {
            try SessionConfig.parse(from: toml)
        }
    }

    @Test func rejectsInvalidTOML() throws {
        let toml = "this is not valid toml {{{"

        #expect(throws: (any Error).self) {
            try SessionConfig.parse(from: toml)
        }
    }
}

@Suite("ConfigLoader")
struct ConfigLoaderTests {

    @Test func loadsFromDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let toml1 = """
        [session]
        name = "alpha"
        type = "local"
        """
        let toml2 = """
        [session]
        name = "beta"
        type = "local"
        """

        let alphaDir = tmpDir.appendingPathComponent("alpha.deck")
        try FileManager.default.createDirectory(at: alphaDir, withIntermediateDirectories: true)
        try toml1.write(to: alphaDir.appendingPathComponent("session.toml"), atomically: true, encoding: .utf8)

        let betaDir = tmpDir.appendingPathComponent("beta.deck")
        try FileManager.default.createDirectory(at: betaDir, withIntermediateDirectories: true)
        try toml2.write(to: betaDir.appendingPathComponent("session.toml"), atomically: true, encoding: .utf8)

        // non-.deck items should be ignored
        try "not a config".write(to: tmpDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let configs = try ConfigLoader.loadAll(from: tmpDir)

        #expect(configs.count == 2)
        #expect(configs[0].name == "alpha")
        #expect(configs[1].name == "beta")
    }

    @Test func createsDirectoryIfMissing() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        #expect(!FileManager.default.fileExists(atPath: tmpDir.path))

        let configs = try ConfigLoader.loadAll(from: tmpDir)

        #expect(FileManager.default.fileExists(atPath: tmpDir.path))
        #expect(configs.isEmpty)
    }

    @Test func ignoresNonTomlFiles() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try "not toml".write(to: tmpDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmpDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        let configs = try ConfigLoader.loadAll(from: tmpDir)
        #expect(configs.isEmpty)
    }
}
