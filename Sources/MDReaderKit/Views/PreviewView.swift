import SwiftUI
import WebKit

/// Preview-related preferences, stored in UserDefaults.
public enum PreviewPreferences {
    public static let loadRemoteImagesKey = "loadRemoteImages"

    /// Remote (http/https) content in the preview is blocked by default:
    /// a markdown file can otherwise embed a tracking pixel that reveals
    /// when/where it is opened. Toggle via View ▸ Load Remote Images.
    public static var loadRemoteImages: Bool {
        UserDefaults.standard.bool(forKey: loadRemoteImagesKey)
    }
}

/// Serves files (images) referenced by relative paths in the markdown from
/// the current document's directory, via the custom mdfile:// scheme.
/// Absolute paths are rejected; reads happen off the main thread.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    final class DirectoryBox {
        var url: URL?
    }

    let directory: DirectoryBox
    /// Tasks that have not been stopped; responding to a stopped task traps.
    private var activeTasks = Set<ObjectIdentifier>()

    init(directory: DirectoryBox) {
        self.directory = directory
    }

    private static let mimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp",
        "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff",
        "heic": "image/heic", "avif": "image/avif", "ico": "image/x-icon",
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let base = directory.url,
            let url = urlSchemeTask.request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let relativePath = components.queryItems?.first(where: { $0.name == "p" })?.value,
            !relativePath.hasPrefix("/"),
            !relativePath.hasPrefix("~")
        else {
            urlSchemeTask.didFailWithError(CocoaError(.fileNoSuchFile))
            return
        }
        // Force directory semantics on the base so relative paths resolve
        // inside it rather than against its parent.
        let directoryBase = URL(fileURLWithPath: base.path, isDirectory: true)
        let fileURL = URL(fileURLWithPath: relativePath, relativeTo: directoryBase).standardizedFileURL
        guard let mime = Self.mimeTypes[fileURL.pathExtension.lowercased()] else {
            urlSchemeTask.didFailWithError(CocoaError(.fileNoSuchFile))
            return
        }
        let taskID = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(taskID)
        DispatchQueue.global(qos: .userInitiated).async {
            let data = try? Data(contentsOf: fileURL)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeTasks.remove(taskID) != nil else { return }
                guard let data else {
                    urlSchemeTask.didFailWithError(CocoaError(.fileNoSuchFile))
                    return
                }
                let response = URLResponse(
                    url: url, mimeType: mime, expectedContentLength: data.count,
                    textEncodingName: nil)
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }
}

/// WKUserContentController retains its handlers; this weak proxy breaks the
/// retain cycle back to the model.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var model: PreviewModel?

    init(_ model: PreviewModel) {
        self.model = model
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        model?.handle(message)
    }
}

/// Owns the WKWebView so it survives view-mode switches (page state and the
/// in-page mermaid SVG cache stay warm).
@MainActor
public final class PreviewModel: NSObject, ObservableObject {
    public let webView: WKWebView

    private let directoryBox = LocalFileSchemeHandler.DirectoryBox()
    public private(set) var isReady = false
    private var pendingText: String?
    private var lastQueuedText: String?
    private var renderTask: Task<Void, Never>?

    /// Fractional source line at the top of the preview, reported when the
    /// user scrolls the preview.
    public var onScroll: ((Double) -> Void)?

    /// Directory used to resolve relative image paths.
    public var documentDirectory: URL? {
        get { directoryBox.url }
        set { directoryBox.url = newValue }
    }

    /// Scroll-sync reporting inside the page is enabled only in Split mode,
    /// so Reader-mode scrolling never does sync work.
    public var syncEnabled = false {
        didSet {
            guard isReady, syncEnabled != oldValue else { return }
            pushSyncEnabled()
        }
    }

    private func pushSyncEnabled() {
        webView.evaluateJavaScript(
            "window.setSyncEnabled(\(syncEnabled ? "true" : "false"));", completionHandler: nil)
    }

    private var defaultsObserver: NSObjectProtocol?
    private var appliedRemotePolicy: Bool?

    override public init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            LocalFileSchemeHandler(directory: directoryBox), forURLScheme: "mdfile")
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        let controller = configuration.userContentController
        controller.add(MessageProxy(self), name: "ready")
        controller.add(MessageProxy(self), name: "scrolled")
        webView.navigationDelegate = self
        // Let the native window background show through (no white flash).
        webView.setValue(false, forKey: "drawsBackground")

        applyRemoteContentPolicy()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyRemoteContentPolicy()
            }
        }

        let root = ResourceLocator.webRoot
        webView.loadFileURL(root.appendingPathComponent("preview.html"), allowingReadAccessTo: root)
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    // MARK: - Remote content blocking

    /// Compiled once per process: blocks every http/https subresource load.
    private static var remoteBlockList: WKContentRuleList?

    private static func loadRemoteBlockList() async -> WKContentRuleList? {
        if let remoteBlockList { return remoteBlockList }
        let rules = #"[{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]"#
        let list = await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "block-remote-content", encodedContentRuleList: rules
            ) { list, _ in
                continuation.resume(returning: list)
            }
        }
        remoteBlockList = list
        return list
    }

    private func applyRemoteContentPolicy() {
        let allowRemote = PreviewPreferences.loadRemoteImages
        guard appliedRemotePolicy != allowRemote else { return }
        appliedRemotePolicy = allowRemote
        Task { @MainActor in
            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            if !allowRemote, let list = await Self.loadRemoteBlockList() {
                controller.add(list)
            }
            if let text = lastQueuedText {
                renderImmediately(text)
            }
        }
    }

    // MARK: - External links

    /// Only these schemes may leave the app when a link is clicked. Anything
    /// else (file://, app-specific schemes, …) from an untrusted markdown
    /// file could launch programs or trigger vulnerable scheme handlers.
    nonisolated public static func isAllowedExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    /// Debounced render used by the SwiftUI update path.
    public func setText(_ text: String) {
        guard text != lastQueuedText else { return }
        lastQueuedText = text
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.renderImmediately(text)
        }
    }

    /// Renders without the debounce (also used by tests).
    public func renderImmediately(_ text: String) {
        lastQueuedText = text
        guard isReady else {
            pendingText = text
            return
        }
        pendingText = nil
        guard let json = Self.jsonString(text) else { return }
        webView.evaluateJavaScript("window.renderMarkdown(\(json));", completionHandler: nil)
    }

    public func scroll(toFractionalLine line: Double) {
        guard isReady, line.isFinite else { return }
        webView.evaluateJavaScript("window.scrollToLine(\(line));", completionHandler: nil)
    }

    fileprivate func handle(_ message: WKScriptMessage) {
        switch message.name {
        case "ready":
            isReady = true
            if syncEnabled {
                pushSyncEnabled()
            }
            if let pendingText {
                renderImmediately(pendingText)
            }
        case "scrolled":
            if let value = message.body as? Double, value.isFinite {
                onScroll?(value)
            }
        default:
            break
        }
    }

    static func jsonString(_ string: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public enum ExportError: LocalizedError {
        case previewNotReady
        case emptyRender

        public var errorDescription: String? {
            switch self {
            case .previewNotReady: return "The preview did not finish loading."
            case .emptyRender: return "The document rendered to an empty page."
            }
        }
    }

    private func evaluateDouble(_ expression: String) async -> Double {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(expression) { result, _ in
                switch result {
                case let value as Double: continuation.resume(returning: value)
                case let value as Int: continuation.resume(returning: Double(value))
                default: continuation.resume(returning: 0)
                }
            }
        }
    }

    /// Renders `text` and captures the full page as PDF data. Works even if
    /// the preview pane is not currently shown (the web view renders
    /// off-screen in its own process).
    public func pdfData(for text: String) async throws -> Data {
        var deadline = Date().addingTimeInterval(10)
        while !isReady && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard isReady else { throw ExportError.previewNotReady }

        // Give the page a sensible width when the pane isn't mounted.
        if webView.bounds.width < 100 {
            webView.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        }
        renderImmediately(text)

        // Wait for layout to settle (mermaid, KaTeX, images): two consecutive
        // identical height readings.
        var lastHeight = -1.0
        var stableReadings = 0
        deadline = Date().addingTimeInterval(5)
        while Date() < deadline && stableReadings < 2 {
            try await Task.sleep(nanoseconds: 200_000_000)
            let height = await evaluateDouble("document.documentElement.scrollHeight")
            if height > 0 && height == lastHeight {
                stableReadings += 1
            } else {
                stableReadings = 0
                lastHeight = height
            }
        }
        guard lastHeight > 0 else { throw ExportError.emptyRender }

        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: lastHeight)
        return try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: configuration) { result in
                continuation.resume(with: result)
            }
        }
    }
}

extension PreviewModel: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Links open in the default browser; the preview itself never
        // navigates. Only safe schemes may leave the app — file:// or custom
        // schemes in a malicious markdown could launch local programs.
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url, Self.isAllowedExternalURL(url) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

public struct PreviewView: NSViewRepresentable {
    let model: PreviewModel
    let text: String

    public init(model: PreviewModel, text: String) {
        self.model = model
        self.text = text
    }

    public func makeNSView(context: Context) -> WKWebView {
        model.setText(text)
        return model.webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        model.setText(text)
    }
}
