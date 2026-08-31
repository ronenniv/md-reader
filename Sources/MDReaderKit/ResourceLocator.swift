import Foundation

public enum ResourceLocator {
    /// Root of the bundled web resources (preview.html + vendor libraries).
    /// Fails loudly rather than showing a silently blank preview.
    public static var webRoot: URL {
        guard let base = Bundle.module.resourceURL?.appendingPathComponent("web"),
              FileManager.default.fileExists(atPath: base.appendingPathComponent("preview.html").path)
        else {
            fatalError(
                """
                MDReader web resources not found in \(Bundle.module.bundlePath). \
                Launch the assembled app (`make run`) — never the bare binary — and make sure \
                Sources/MDReaderKit/Resources/web contains preview.html and vendor/.
                """
            )
        }
        return base
    }
}
