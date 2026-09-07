import AppKit
import Foundation

/// Anchors Bundle(for:) lookups to wherever MDReaderKit's code is loaded
/// (the app binary, or the test bundle under `swift test`).
private final class BundleAnchor {}

public enum ResourceLocator {
    static let bundleName = "md-reader_MDReaderKit.bundle"

    /// Root of the bundled web resources (preview.html + vendor libraries).
    ///
    /// Never touches the generated Bundle.module accessor: that accessor
    /// fatalError-crashes internally when it cannot load the bundle (seen in
    /// the field when macOS quarantine blocks in-process reads of a fresh,
    /// un-notarized install) — before any recovery code can run. This does
    /// its own search and shows a recovery dialog on failure instead.
    public static var webRoot: URL {
        if let root = locateWebRoot() {
            return root
        }

        let message = """
            MDReader could not load its bundled resources.

            The app is likely quarantined (this happens to not-yet-notarized \
            downloads). Run this in Terminal, then reopen MDReader:

            xattr -dr com.apple.quarantine /Applications/MDReader.app

            (Building from source? Launch the assembled app with `make run`, \
            never the bare binary.)
            """
        if NSApp != nil {
            let alert = NSAlert()
            alert.messageText = "MDReader cannot start"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.runModal()
        }
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }

    static func locateWebRoot() -> URL? {
        let anchor = Bundle(for: BundleAnchor.self)
        let candidates: [URL?] = [
            Bundle.main.resourceURL,                          // assembled app
            anchor.resourceURL,                               // host bundle resources
            anchor.bundleURL.deletingLastPathComponent(),     // swift test: next to the .xctest
            Bundle.main.bundleURL,                            // bare-binary dev runs
        ]
        for case let base? in candidates {
            let webRoot = base
                .appendingPathComponent(bundleName)
                .appendingPathComponent("web")
            if FileManager.default.fileExists(
                atPath: webRoot.appendingPathComponent("preview.html").path)
            {
                return webRoot
            }
        }
        return nil
    }
}
