import AppKit
import Foundation

public enum ResourceLocator {
    /// Root of the bundled web resources (preview.html + vendor libraries).
    ///
    /// Looks in Bundle.main first (the assembled app) without touching the
    /// generated Bundle.module accessor, because that accessor fatalError-
    /// crashes when macOS quarantine blocks in-process reads (e.g. launching
    /// a freshly Homebrew-installed, not-yet-notarized build). This path can
    /// fail with a helpful dialog instead. Falls back to Bundle.module for
    /// the `swift test` context, where Bundle.main is the test runner.
    public static var webRoot: URL {
        let bundleName = "md-reader_MDReaderKit.bundle"
        if let candidate = Bundle.main.resourceURL?
            .appendingPathComponent(bundleName)
            .appendingPathComponent("web"),
            FileManager.default.fileExists(atPath: candidate.appendingPathComponent("preview.html").path)
        {
            return candidate
        }

        if let candidate = Bundle.module.resourceURL?.appendingPathComponent("web"),
            FileManager.default.fileExists(atPath: candidate.appendingPathComponent("preview.html").path)
        {
            return candidate
        }

        let message = """
            MDReader could not load its bundled resources.

            If you installed via Homebrew, the app is likely still quarantined. \
            Run this in Terminal, then reopen MDReader:

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
}
