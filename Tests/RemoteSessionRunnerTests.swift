import Testing
import Foundation
@testable import DeckLib

@Suite("Remote Session Runner")
struct RemoteSessionRunnerTests {

    private func makeRemoteSession(
        name: String = "remote-test",
        sshCommand: String = "ssh user@host",
        provision: String? = nil,
        deprovision: String? = nil,
        readyCheck: String? = nil,
        readyTimeout: Int = 5
    ) -> Session {
        var hostLines = "ssh = \"\(sshCommand)\""
        if let p = provision { hostLines += "\nprovision = \"\(p)\"" }
        if let d = deprovision { hostLines += "\ndeprovision = \"\(d)\"" }
        if let r = readyCheck { hostLines += "\nready_check = \"\(r)\"" }
        hostLines += "\nready_timeout_seconds = \(readyTimeout)"

        let toml = """
        [session]
        name = "\(name)"
        type = "remote"

        [host]
        \(hostLines)

        [startup]
        working_dir = "/tmp"
        steps = ["echo hello"]
        """
        return Session(config: try! SessionConfig.parse(from: toml))
    }

    @Test func requiresHostConfig() async {
        let toml = """
        [session]
        name = "no-host"
        type = "remote"
        """
        let session = Session(config: try! SessionConfig.parse(from: toml))
        let runner = RemoteSessionRunner(session: session)

        do {
            try await runner.start()
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(session.state == .stopped)
        }
    }

    @Test func cannotStartWhenNotStopped() async throws {
        let session = makeRemoteSession()
        try session.transitionTo(.starting)

        let runner = RemoteSessionRunner(session: session)

        do {
            try await runner.start()
            #expect(Bool(false), "Should have thrown")
        } catch let error as SessionRunnerError {
            #expect(error.description.contains("Cannot start"))
        }
    }

    @Test func provisioningFailureStopsSession() async {
        // Use a command that will fail
        let session = makeRemoteSession(
            name: "prov-fail",
            provision: "false"  // always fails
        )
        let runner = RemoteSessionRunner(session: session)

        do {
            try await runner.start()
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(session.state == .stopped)
        }
    }

    @Test func readyCheckTimeoutStopsSession() async {
        // Use a ready check that always fails, with short timeout
        let session = makeRemoteSession(
            name: "ready-timeout",
            readyCheck: "false",  // always fails
            readyTimeout: 3
        )
        let runner = RemoteSessionRunner(session: session)

        do {
            try await runner.start()
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(session.state == .stopped)
        }
    }

    @Test func intentionalStopFlag() {
        let session = makeRemoteSession()
        let runner = RemoteSessionRunner(session: session)

        #expect(!runner.isIntentionalStop)
    }

    @Test func sessionTypeIsRemote() {
        let session = makeRemoteSession()
        #expect(session.config.type == .remote)
        #expect(session.config.host != nil)
        #expect(session.config.host?.ssh == "ssh user@host")
    }
}
