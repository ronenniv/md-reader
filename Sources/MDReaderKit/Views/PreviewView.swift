import SwiftUI
import WebKit

/// Serves files (images) referenced by relative paths in the markdown from
/// the current document's directory, via the custom mdfile:// scheme.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    final class DirectoryBox {
        var url: URL?
    }

    let directory: DirectoryBox

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
            let relativePath = components.queryItems?.first(where: { $0.name == "p" })?.value
        else {
            urlSchemeTask.didFailWithError(CocoaError(.fileNoSuchFile))
            return
        }
        let fileURL = URL(fileURLWithPath: relativePath, relativeTo: base).standardizedFileURL
        guard
            let mime = Self.mimeTypes[fileURL.pathExtension.lowercased()],
            let data = try? Data(contentsOf: fileURL)
        else {
            urlSchemeTask.didFailWithError(CocoaError(.fileNoSuchFile))
            return
        }
        let response = URLResponse(
            url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
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
    private var isReady = false
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

        let root = ResourceLocator.webRoot
        webView.loadFileURL(root.appendingPathComponent("preview.html"), allowingReadAccessTo: root)
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
}

extension PreviewModel: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Links open in the default browser; the preview itself never navigates.
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url {
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
