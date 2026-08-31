import Foundation
import Testing
import WebKit

@testable import MDReaderKit

@Suite struct ExternalLinkPolicyTests {
    @Test func allowsWebAndMailLinks() {
        #expect(PreviewModel.isAllowedExternalURL(URL(string: "https://example.com")!))
        #expect(PreviewModel.isAllowedExternalURL(URL(string: "http://example.com")!))
        #expect(PreviewModel.isAllowedExternalURL(URL(string: "mailto:a@b.c")!))
        #expect(PreviewModel.isAllowedExternalURL(URL(string: "HTTPS://EXAMPLE.COM")!))
    }

    @Test func blocksLocalAndCustomSchemes() {
        // file:// would LAUNCH the target via NSWorkspace.open.
        #expect(!PreviewModel.isAllowedExternalURL(URL(string: "file:///Applications/Calculator.app")!))
        #expect(!PreviewModel.isAllowedExternalURL(URL(string: "shortcuts://run-shortcut?name=x")!))
        #expect(!PreviewModel.isAllowedExternalURL(URL(string: "x-apple.systempreferences:com.apple.preference")!))
        #expect(!PreviewModel.isAllowedExternalURL(URL(string: "mdfile:///?p=x.png")!))
        #expect(!PreviewModel.isAllowedExternalURL(URL(string: "javascript:alert(1)")!))
    }
}

/// Exercises LocalFileSchemeHandler with a mock WKURLSchemeTask.
@MainActor
@Suite final class SchemeHandlerTests {
    final class MockTask: NSObject, WKURLSchemeTask {
        let request: URLRequest
        var response: URLResponse?
        var received = Data()
        var finished = false
        var failed: Error?

        init(url: URL) {
            request = URLRequest(url: url)
        }

        func didReceive(_ response: URLResponse) { self.response = response }
        func didReceive(_ data: Data) { received.append(data) }
        func didFinish() { finished = true }
        func didFailWithError(_ error: Error) { failed = error }
    }

    private let directory: URL
    private let handler: LocalFileSchemeHandler
    private let webView = WKWebView()

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdreader-scheme-\(UUID().uuidString)/docs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: directory.appendingPathComponent("img.png"))
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D]).write(
            to: directory.deletingLastPathComponent().appendingPathComponent("parent.png"))
        try "secret".write(
            to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let box = LocalFileSchemeHandler.DirectoryBox()
        box.url = directory
        handler = LocalFileSchemeHandler(directory: box)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func run(_ path: String) async -> MockTask {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
        let task = MockTask(url: URL(string: "mdfile:///?p=\(encoded)")!)
        handler.webView(webView, start: task)
        // The handler reads off the main thread and responds on main.
        for _ in 0..<100 {
            if task.finished || task.failed != nil { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return task
    }

    @Test func servesRelativeImage() async {
        let task = await run("img.png")
        #expect(task.finished)
        #expect(task.failed == nil)
        #expect(task.response?.mimeType == "image/png")
        #expect(task.received.count == 4)
    }

    @Test func servesParentRelativeImage() async {
        let task = await run("../parent.png")
        #expect(task.finished)
        #expect(task.received.count == 5)
    }

    @Test func rejectsAbsolutePaths() async {
        let absolute = directory.appendingPathComponent("img.png").path
        let task = await run(absolute)
        #expect(!task.finished)
        #expect(task.failed != nil)
    }

    @Test func rejectsTildePaths() async {
        let task = await run("~/Pictures/img.png")
        #expect(!task.finished)
        #expect(task.failed != nil)
    }

    @Test func rejectsNonImageExtensions() async {
        let task = await run("notes.txt")
        #expect(!task.finished)
        #expect(task.failed != nil)
        #expect(task.received.isEmpty)
    }

    @Test func rejectsMissingFile() async {
        let task = await run("nope.png")
        #expect(!task.finished)
        #expect(task.failed != nil)
    }
}