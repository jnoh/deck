import Testing
import Foundation
@testable import DeckLib

@Suite("Session Status")
struct SessionStatusTests {

    @Test func parsesStatusUpdate() {
        let json = """
        {"type":"status","state":"working","desc":"Editing main.py","icon":"⚡"}
        """
        let update = StatusUpdate.parse(json: json)!
        #expect(update.type == .status)
        #expect(update.state == "working")
        #expect(update.desc == "Editing main.py")
        #expect(update.icon == "⚡")
    }

    @Test func parsesNotifyUpdate() {
        let json = """
        {"type":"notify","text":"Need your input","level":"warning"}
        """
        let update = StatusUpdate.parse(json: json)!
        #expect(update.type == .notify)
        #expect(update.text == "Need your input")
        #expect(update.level == "warning")
    }

    @Test func parsesClearUpdate() {
        let json = """
        {"type":"clear"}
        """
        let update = StatusUpdate.parse(json: json)!
        #expect(update.type == .clear)
    }

    @Test func rejectsInvalidJSON() {
        #expect(StatusUpdate.parse(json: "not json") == nil)
        #expect(StatusUpdate.parse(json: "{}") == nil)
        #expect(StatusUpdate.parse(json: "{\"type\":\"unknown\"}") == nil)
    }

    @Test func statusAppliesUpdate() {
        let status = SessionStatus()

        status.apply(StatusUpdate(
            type: .status, state: "working", desc: "Editing", icon: "⚡", text: nil, level: nil
        ))

        #expect(status.customState == "working")
        #expect(status.desc == "Editing")
        #expect(status.icon == "⚡")
    }

    @Test func notifyIncrementsCount() {
        let status = SessionStatus()
        #expect(status.notificationCount == 0)

        status.apply(StatusUpdate(
            type: .notify, state: nil, desc: nil, icon: nil, text: "hello", level: nil
        ))
        #expect(status.notificationCount == 1)

        status.apply(StatusUpdate(
            type: .notify, state: nil, desc: nil, icon: nil, text: "again", level: nil
        ))
        #expect(status.notificationCount == 2)
    }

    @Test func clearResetsEverything() {
        let status = SessionStatus()
        status.apply(StatusUpdate(
            type: .status, state: "working", desc: "test", icon: "🔥", text: nil, level: nil
        ))
        status.apply(StatusUpdate(
            type: .notify, state: nil, desc: nil, icon: nil, text: "x", level: nil
        ))

        #expect(status.customState == "working")
        #expect(status.notificationCount == 1)

        status.apply(StatusUpdate(type: .clear, state: nil, desc: nil, icon: nil, text: nil, level: nil))

        #expect(status.customState == nil)
        #expect(status.desc == nil)
        #expect(status.icon == nil)
        #expect(status.notificationCount == 0)
    }

    @Test func needsAttentionForNeedsInput() {
        let status = SessionStatus()
        #expect(!status.needsAttention)

        status.apply(StatusUpdate(
            type: .status, state: "needs-input", desc: nil, icon: nil, text: nil, level: nil
        ))
        #expect(status.needsAttention)
    }

    @Test func needsAttentionForNotifications() {
        let status = SessionStatus()
        #expect(!status.needsAttention)

        status.apply(StatusUpdate(
            type: .notify, state: nil, desc: nil, icon: nil, text: "hi", level: nil
        ))
        #expect(status.needsAttention)
    }

    @Test func clearAttentionResetsNotificationCount() {
        let status = SessionStatus()
        status.apply(StatusUpdate(
            type: .notify, state: nil, desc: nil, icon: nil, text: "hi", level: nil
        ))
        #expect(status.notificationCount == 1)

        status.clearAttention()
        #expect(status.notificationCount == 0)
        #expect(!status.needsAttention)
    }

    @Test func sessionHasStatus() {
        let config = try! SessionConfig.parse(from: """
        [session]
        name = "test"
        type = "local"
        """)
        let session = Session(config: config)
        #expect(session.status.customState == nil)
        #expect(session.status.desc == nil)
    }

    @Test func packageDirDefaultsToNil() throws {
        let config = try SessionConfig.parse(from: """
        [session]
        name = "test"
        type = "local"
        """)
        #expect(config.packageDir == nil)
        #expect(!config.isPackage)
    }

    @Test func loadsPackageDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-pkg-\(UUID().uuidString)")
        let pkgDir = tmpDir.appendingPathComponent("test.deck")
        try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let toml = """
        [session]
        name = "pkg-test"
        type = "local"
        """
        try toml.write(to: pkgDir.appendingPathComponent("session.toml"), atomically: true, encoding: .utf8)
        try "#!/bin/bash\necho hi".write(to: pkgDir.appendingPathComponent("start.sh"), atomically: true, encoding: .utf8)

        let configs = try ConfigLoader.loadAll(from: tmpDir)
        #expect(configs.count == 1)
        #expect(configs[0].name == "pkg-test")
        #expect(configs[0].isPackage)
        #expect(configs[0].startScript != nil)
    }

    @Test func deckPrefixParsing() {
        let title = "deck:{\"type\":\"status\",\"state\":\"working\",\"desc\":\"test\"}"
        #expect(title.hasPrefix("deck:"))

        let json = String(title.dropFirst(5))
        let update = StatusUpdate.parse(json: json)
        #expect(update != nil)
        #expect(update?.state == "working")
    }
}
