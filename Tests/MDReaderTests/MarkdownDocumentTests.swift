import Foundation
import Testing

@testable import MDReaderKit

@Suite struct MarkdownDocumentTests {
    @Test func utf8RoundTrip() throws {
        let original = "# Héllo 👋\n\nSome **markdown** with unicode: π ≈ 3.14159\n"
        let document = try MarkdownDocument(data: Data(original.utf8))
        #expect(document.text == original)
        #expect(document.data() == Data(original.utf8))
    }

    @Test func latin1Fallback() throws {
        // 0xE9 is "é" in ISO-Latin-1 but invalid as a standalone UTF-8 byte.
        let data = Data([0x63, 0x61, 0x66, 0xE9])
        let document = try MarkdownDocument(data: data)
        #expect(document.text == "café")
    }

    @Test func emptyFile() throws {
        let document = try MarkdownDocument(data: Data())
        #expect(document.text == "")
        #expect(document.data() == Data())
    }

    @Test func writesUTF8() {
        var document = MarkdownDocument()
        document.text = "naïve — em dash"
        #expect(String(data: document.data(), encoding: .utf8) == "naïve — em dash")
    }
}

@Suite struct TextMetricsTests {
    @Test func wordCount() {
        #expect(TextMetrics.wordCount(of: "") == 0)
        #expect(TextMetrics.wordCount(of: "one") == 1)
        #expect(TextMetrics.wordCount(of: "# Title\n\nsome words here\n") == 5)
    }

    @Test func readingMinutes() {
        #expect(TextMetrics.readingMinutes(forWordCount: 0) == 1)
        #expect(TextMetrics.readingMinutes(forWordCount: 199) == 1)
        #expect(TextMetrics.readingMinutes(forWordCount: 201) == 2)
    }
}

@Suite struct ExternalChangeResolverTests {
    @Test func ignoreWhenDiskUnchanged() {
        #expect(ExternalChangeResolver.resolve(disk: "a", lastKnownDisk: "a", editor: "b") == .ignore)
    }

    @Test func adoptOwnSave() {
        #expect(
            ExternalChangeResolver.resolve(disk: "edited", lastKnownDisk: "old", editor: "edited")
                == .adoptAsSaved)
    }

    @Test func silentReloadWhenClean() {
        #expect(
            ExternalChangeResolver.resolve(disk: "new", lastKnownDisk: "old", editor: "old")
                == .reloadSilently)
    }

    @Test func conflictWhenBothChanged() {
        #expect(
            ExternalChangeResolver.resolve(disk: "theirs", lastKnownDisk: "old", editor: "mine")
                == .conflict)
    }
}
