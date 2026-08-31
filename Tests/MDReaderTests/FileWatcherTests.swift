import Foundation
import Testing

@testable import MDReaderKit

/// FileWatcher delivers callbacks on the main queue, so these tests are
/// main-actor: awaiting between polls lets the main queue process events.
@MainActor
@Suite final class FileWatcherTests {
    private let directory: URL
    private let fileURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdreader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("watched.md")
        try "initial".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func waitUntil(
        timeout: TimeInterval = 5, _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    @Test func detectsInPlaceWrite() async throws {
        let watcher = FileWatcher()
        nonisolated(unsafe) var fired = false
        watcher.onChange = { fired = true }
        watcher.watch(fileURL)

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" appended".utf8))
        try handle.close()

        #expect(await waitUntil { fired }, "in-place write must fire onChange")
        watcher.stop()
    }

    @Test func detectsAtomicReplaceAndReArms() async throws {
        let watcher = FileWatcher()
        nonisolated(unsafe) var count = 0
        watcher.onChange = { count += 1 }
        watcher.watch(fileURL)

        // .atomically writes a temp file and renames it over the target,
        // replacing the inode — exactly what most editors do on save.
        try "replaced content".write(to: fileURL, atomically: true, encoding: .utf8)
        #expect(await waitUntil { count >= 1 }, "atomic replace must fire onChange")

        // The watcher must have re-armed on the new inode.
        let baseline = count
        try "replaced again".write(to: fileURL, atomically: true, encoding: .utf8)
        #expect(await waitUntil { count > baseline }, "watcher must re-arm after atomic replace")
        watcher.stop()
    }

    @Test func externalDeleteDoesNotCrash() async throws {
        let watcher = FileWatcher()
        watcher.onChange = {}
        watcher.watch(fileURL)
        try FileManager.default.removeItem(at: fileURL)
        // Give the event and the re-arm path time to run.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        watcher.stop()
    }

    @Test func stopSilencesCallbacks() async throws {
        let watcher = FileWatcher()
        nonisolated(unsafe) var fired = false
        watcher.onChange = { fired = true }
        watcher.watch(fileURL)
        watcher.stop()
        try "changed after stop".write(to: fileURL, atomically: true, encoding: .utf8)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(!fired)
    }
}
