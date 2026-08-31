import Foundation

/// Watches a file for external changes. Re-arms after atomic saves (which
/// replace the inode via rename) and goes quiet if the file disappears.
/// All state is confined to the main queue.
public final class FileWatcher: ObservableObject {
    private var source: DispatchSourceFileSystemObject?
    public private(set) var url: URL?
    /// Called on the main queue whenever the file's content may have changed.
    public var onChange: (() -> Void)?

    public init() {}

    deinit {
        source?.cancel()
    }

    public func watch(_ url: URL) {
        stop()
        self.url = url
        arm()
    }

    public func stop() {
        source?.cancel()
        source = nil
        url = nil
    }

    private func arm() {
        guard let url else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        src.setCancelHandler { close(fd) }
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            self.handleEvent(src.data)
        }
        source = src
        src.resume()
    }

    private func handleEvent(_ flags: DispatchSource.FileSystemEvent) {
        if flags.contains(.rename) || flags.contains(.delete) {
            // Atomic saves replace the inode: our fd now points at the old
            // file. Re-arm on the path if a file still exists there.
            source?.cancel()
            source = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, let url = self.url else { return }
                if FileManager.default.fileExists(atPath: url.path) {
                    self.arm()
                    self.onChange?()
                }
            }
        } else {
            onChange?()
        }
    }
}

/// What to do when the file on disk may have changed under an open document.
public enum ExternalChangeAction: Equatable, Sendable {
    /// Disk still matches what we last knew — nothing happened.
    case ignore
    /// Disk now matches the editor: it was our own save (or an identical
    /// external write) — adopt it as the new baseline.
    case adoptAsSaved
    /// The editor has no unsaved edits — take the disk version silently.
    case reloadSilently
    /// Unsaved edits diverge from a changed disk — the user must decide.
    case conflict
}

public enum ExternalChangeResolver {
    public static func resolve(disk: String, lastKnownDisk: String, editor: String) -> ExternalChangeAction {
        if disk == lastKnownDisk { return .ignore }
        if disk == editor { return .adoptAsSaved }
        if editor == lastKnownDisk { return .reloadSilently }
        return .conflict
    }
}
