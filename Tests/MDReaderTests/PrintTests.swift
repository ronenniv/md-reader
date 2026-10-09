import AppKit
import Foundation
import PDFKit
import Testing

@testable import MDReaderKit

/// Drives the real print path headlessly: the print operation is pointed at
/// a PDF file instead of a printer, with the panel disabled and an offscreen
/// window standing in for the document window, and the resulting pages are
/// inspected with PDFKit.
@MainActor
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["MDREADER_SKIP_WEBVIEW_TESTS"] != "1")
)
final class PrintTests {
    private let model = PreviewModel()
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled], backing: .buffered, defer: false)
    private let output: URL

    init() {
        output = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdreader-print-\(UUID().uuidString).pdf")
    }

    deinit {
        try? FileManager.default.removeItem(at: output)
    }

    private func printInfoSavingToFile() -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)  // US Letter
        info.orientation = .portrait
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        return info
    }

    @Test func longDocumentPaginatesAcrossLetterPages() async throws {
        let markdown = (1...120).map { "## Section \($0)\n\nBody text for section \($0).\n" }.joined(separator: "\n")
        let printed = try await model.printDocument(
            markdown, jobTitle: "Print Test", in: window,
            printInfo: printInfoSavingToFile(), showsPanel: false)
        #expect(printed, "print operation reported failure")

        let pdf = try #require(PDFDocument(url: output), "print operation wrote no PDF")
        #expect(pdf.pageCount >= 3, "expected several pages, got \(pdf.pageCount)")
        let bounds = try #require(pdf.page(at: 0)?.bounds(for: .mediaBox))
        #expect(abs(bounds.width - 612) < 1 && abs(bounds.height - 792) < 1, "page should be US Letter")
        let firstPageText = pdf.page(at: 0)?.string ?? ""
        #expect(firstPageText.contains("Section 1"), "first page should carry the document start")
    }

    @Test func shortDocumentIsOnePage() async throws {
        let printed = try await model.printDocument(
            "# Title\n\nOne paragraph.\n", jobTitle: "Print Test", in: window,
            printInfo: printInfoSavingToFile(), showsPanel: false)
        #expect(printed)
        let pdf = try #require(PDFDocument(url: output))
        #expect(pdf.pageCount == 1)
    }
}
