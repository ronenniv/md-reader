import Foundation
import Testing
import WebKit

@testable import MDReaderKit

/// Exercises the real JS pipeline (markdown-it + KaTeX + highlight.js +
/// mermaid) inside a headless WKWebView, loading the actual bundled
/// preview.html and vendored libraries.
///
/// Serialized: WKWebView instances are heavyweight; one at a time keeps the
/// tests deterministic.
@MainActor
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["MDREADER_SKIP_WEBVIEW_TESTS"] != "1")
)
final class PreviewRenderTests {
    private let model: PreviewModel

    init() async throws {
        model = PreviewModel()
        model.webView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let ready = await poll("window.__ready === true", timeout: 20)
        try #require(ready, "preview.html never became ready")
    }

    private func evalBool(_ expression: String) async -> Bool {
        await withCheckedContinuation { continuation in
            model.webView.evaluateJavaScript(expression) { result, _ in
                continuation.resume(returning: result as? Bool ?? false)
            }
        }
    }

    private func evalInt(_ expression: String) async -> Int {
        await withCheckedContinuation { continuation in
            model.webView.evaluateJavaScript(expression) { result, _ in
                continuation.resume(returning: result as? Int ?? -1)
            }
        }
    }

    private func poll(_ expression: String, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await evalBool(expression) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return await evalBool(expression)
    }

    private func render(_ markdown: String) async throws {
        model.renderImmediately(markdown)
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test func gfmBasics() async throws {
        try await render(
            """
            | a | b |
            |---|---|
            | 1 | 2 |

            - [ ] todo
            - [x] done

            ~~gone~~ and https://example.com autolinked
            """
        )
        #expect(await poll("document.querySelectorAll('table').length === 1"), "table")
        #expect(
            await poll("document.querySelectorAll(\"input[type=checkbox]\").length === 2"),
            "task checkboxes")
        #expect(await poll("document.querySelectorAll('s').length === 1"), "strikethrough")
        #expect(
            await poll("document.querySelectorAll(\"a[href='https://example.com']\").length === 1"),
            "autolink")
    }

    @Test func codeHighlighting() async throws {
        try await render("```swift\nlet x: Int = 1\n```\n")
        #expect(
            await poll("document.querySelectorAll('code.hljs.language-swift').length === 1"),
            "highlighted swift fence")
        #expect(
            await poll("document.querySelectorAll('code.hljs .hljs-keyword').length >= 1"),
            "keyword token spans")
    }

    @Test func mathRendersAndProseDollarsDoNot() async throws {
        try await render(
            """
            Inline $x^2$ math.

            $$\\int_0^1 x\\,dx$$

            Prices are $5 or $10 today, and `$y$` is code.
            """
        )
        #expect(await poll("document.querySelectorAll('.katex').length >= 2"), "katex output")
        // The code span must survive as code, not math.
        #expect(
            await poll("[...document.querySelectorAll('code')].some(c => c.textContent === '$y$')"),
            "code span kept literal")
        // "$5 or $10" must not produce math beyond the two real formulas.
        let count = await evalInt("document.querySelectorAll('.katex').length")
        #expect(count == 2, "prose dollars must not become math")
    }

    @Test func rawHTMLIsEscaped() async throws {
        try await render("<b>not bold</b>\n")
        #expect(
            await poll(
                "document.querySelectorAll('#content b').length === 0"
                    + " && document.body.textContent.includes('<b>')"),
            "raw html escaped")
    }

    @Test func mermaidRendersAndErrorsInline() async throws {
        try await render("```mermaid\nflowchart LR\n  A --> B\n```\n")
        #expect(
            await poll("document.querySelectorAll('.mermaid-diagram svg').length === 1", timeout: 20),
            "mermaid diagram svg")

        try await render("```mermaid\nthis is not a diagram\n```\n")
        #expect(
            await poll("document.querySelectorAll('.mermaid-error').length === 1", timeout: 20),
            "mermaid inline error box")
    }

    @Test func dataLineStampsForScrollSync() async throws {
        try await render("# one\n\ntwo\n\nthree\n")
        #expect(
            await poll("document.querySelectorAll('[data-line]').length >= 3"),
            "data-line attributes")
        #expect(
            await poll("document.querySelector('h1').dataset.line === '0'"),
            "heading maps to line 0")
    }

    @Test func relativeImagesRoutedThroughScheme() async throws {
        try await render("![pic](./img.png)\n")
        #expect(
            await poll(
                "document.querySelector('img') !== null"
                    + " && document.querySelector('img').src.startsWith('mdfile://')"),
            "relative image rewritten to mdfile scheme")
    }

    @Test func absoluteImageURLsUntouched() async throws {
        try await render("![pic](https://example.com/img.png)\n")
        #expect(
            await poll(
                "document.querySelector('img') !== null"
                    + " && document.querySelector('img').src === 'https://example.com/img.png'"),
            "absolute image src preserved")
    }

    @Test func pdfExportProducesRealPDF() async throws {
        let data = try await model.pdfData(
            for: "# PDF Export\n\nSome **bold** text and `code`.\n\n- a list item\n")
        #expect(data.count > 1000, "PDF should have real content")
        #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-", "must be a PDF file")
    }

    @Test func scrollToLineIsCallable() async throws {
        try await render(String(repeating: "line\n\n", count: 200))
        #expect(await poll("typeof window.scrollToLine === 'function'"), "scrollToLine exists")
        model.scroll(toFractionalLine: 100)
        #expect(await poll("window.scrollY > 0", timeout: 5), "scrollToLine moved the page")
    }
}
