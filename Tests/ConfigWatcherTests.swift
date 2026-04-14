import Testing
import Foundation
@testable import DeckLib

@Suite("Config Watcher")
struct ConfigWatcherTests {

    @Test func detectsNewFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let expectation = Expectation()

        let watcher = ConfigWatcher(directory: tmpDir) {
            expectation.fulfill()
        }
        try watcher.start()

        // Write a new file
        try "test".write(
            to: tmpDir.appendingPathComponent("new.toml"),
            atomically: true,
            encoding: .utf8
        )

        try await Task.sleep(for: .seconds(1))
        #expect(expectation.isFulfilled)

        watcher.stop()
    }

    @Test func detectsModifiedFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let filePath = tmpDir.appendingPathComponent("existing.toml")
        try "original".write(to: filePath, atomically: true, encoding: .utf8)

        let expectation = Expectation()

        let watcher = ConfigWatcher(directory: tmpDir) {
            expectation.fulfill()
        }
        try watcher.start()

        // Modify the file
        try "modified".write(to: filePath, atomically: true, encoding: .utf8)

        try await Task.sleep(for: .seconds(1))
        #expect(expectation.isFulfilled)

        watcher.stop()
    }

    @Test func detectsDeletedFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let filePath = tmpDir.appendingPathComponent("todelete.toml")
        try "data".write(to: filePath, atomically: true, encoding: .utf8)

        let expectation = Expectation()

        let watcher = ConfigWatcher(directory: tmpDir) {
            expectation.fulfill()
        }
        try watcher.start()

        try FileManager.default.removeItem(at: filePath)

        try await Task.sleep(for: .seconds(1))
        #expect(expectation.isFulfilled)

        watcher.stop()
    }

    @Test func createsDirectoryIfMissing() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-watcher-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = ConfigWatcher(directory: tmpDir) {}
        try watcher.start()

        #expect(FileManager.default.fileExists(atPath: tmpDir.path))
        watcher.stop()
    }
}

// Simple thread-safe expectation helper
private final class Expectation: @unchecked Sendable {
    private let lock = NSLock()
    private var _fulfilled = false

    var isFulfilled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _fulfilled
    }

    func fulfill() {
        lock.lock()
        _fulfilled = true
        lock.unlock()
    }
}
