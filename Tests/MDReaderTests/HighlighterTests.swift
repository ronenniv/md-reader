import AppKit
import SwiftUI
import Testing

@testable import MDReaderKit

@MainActor
@Suite struct HighlighterTests {
    private func highlighted(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownHighlighter().highlight(storage)
        return storage
    }

    private func color(_ storage: NSTextStorage, at index: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func font(_ storage: NSTextStorage, at index: Int) -> NSFont? {
        storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    @Test func headingStyling() {
        let storage = highlighted("# Title")
        // The hash delimiter recedes…
        #expect(color(storage, at: 0) == .tertiaryLabelColor)
        // …while the heading text pops in accent + heading font.
        #expect(color(storage, at: 3) == .controlAccentColor)
        #expect(font(storage, at: 3) == MarkdownHighlighter.headingFont)
    }

    @Test func h3UsesBoldNotLarger() {
        let storage = highlighted("### Small heading")
        #expect(font(storage, at: 5) == MarkdownHighlighter.boldFont)
    }

    @Test func boldContentAndDimmedDelimiters() {
        let storage = highlighted("some **bold** text")
        #expect(font(storage, at: 8) == MarkdownHighlighter.boldFont)  // inside "bold"
        #expect(color(storage, at: 5) == .tertiaryLabelColor)  // "**"
        #expect(font(storage, at: 0) == MarkdownHighlighter.baseFont)  // "some"
    }

    @Test func codeSpan() {
        let storage = highlighted("call `render()` now")
        #expect(color(storage, at: 7) == .systemPink)
        #expect(storage.attribute(.backgroundColor, at: 7, effectiveRange: nil) != nil)
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func fenceInteriorSuppressesInlineRules() {
        let storage = highlighted("```\nsome **not bold** code\n```\nafter **bold**")
        let text = storage.string as NSString
        let interior = text.range(of: "not bold").location
        // Inside the fence: no bold font, but the code background tint.
        #expect(font(storage, at: interior) == MarkdownHighlighter.baseFont)
        #expect(storage.attribute(.backgroundColor, at: interior, effectiveRange: nil) != nil)
        // Outside the fence bold still applies.
        let afterBold = text.range(of: "**bold**").location + 2
        #expect(font(storage, at: afterBold) == MarkdownHighlighter.boldFont)
    }

    @Test func blockquoteAndListMarkers() {
        let quoted = highlighted("> quoted text")
        #expect(color(quoted, at: 3) == .systemGreen)

        let list = highlighted("- item")
        #expect(color(list, at: 0) == .controlAccentColor)
        #expect(color(list, at: 3) == .labelColor)
    }

    @Test func linkStyling() {
        let storage = highlighted("see [docs](https://example.com) here")
        let text = storage.string as NSString
        let label = text.range(of: "docs").location
        let url = text.range(of: "https").location
        #expect(color(storage, at: label) == .linkColor)
        #expect(color(storage, at: url) == .tertiaryLabelColor)
    }
}

@MainActor
@Suite struct EditorCoordinatorTests {
    @Test func applyExternalTextPreservesSelection() {
        let model = EditorModel()
        model.textView.string = "hello world"
        model.textView.setSelectedRange(NSRange(location: 6, length: 5))

        model.applyExternalText("hello brave world")
        #expect(model.textView.string == "hello brave world")
        #expect(model.textView.selectedRange() == NSRange(location: 6, length: 5))
    }

    @Test func applyExternalTextClampsSelection() {
        let model = EditorModel()
        model.textView.string = "a long piece of text"
        model.textView.setSelectedRange(NSRange(location: 10, length: 5))

        model.applyExternalText("short")
        #expect(model.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func textDidChangeWritesBackExactlyOnce() {
        nonisolated(unsafe) var bindingText = "start"
        nonisolated(unsafe) var writeCount = 0
        let binding = Binding<String>(
            get: { bindingText },
            set: { newValue in
                bindingText = newValue
                writeCount += 1
            }
        )
        let model = EditorModel()
        let view = EditorView(text: binding, model: model)
        let coordinator = view.makeCoordinator()
        model.textView.delegate = coordinator
        model.applyExternalText("start")

        // Simulate the user typing.
        model.textView.string = "start typed"
        coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: model.textView))

        #expect(bindingText == "start typed")
        #expect(writeCount == 1)
    }

    @Test func externalUpdateDoesNotEchoIntoBinding() {
        nonisolated(unsafe) var bindingText = "start"
        nonisolated(unsafe) var writeCount = 0
        let binding = Binding<String>(
            get: { bindingText },
            set: { newValue in
                bindingText = newValue
                writeCount += 1
            }
        )
        let model = EditorModel()
        let view = EditorView(text: binding, model: model)
        let coordinator = view.makeCoordinator()
        model.textView.delegate = coordinator

        model.applyExternalText("from outside")
        #expect(writeCount == 0)
        #expect(bindingText == "start")
    }

    @Test func smartSubstitutionsDisabled() {
        let model = EditorModel()
        #expect(!model.textView.isAutomaticQuoteSubstitutionEnabled)
        #expect(!model.textView.isAutomaticDashSubstitutionEnabled)
        #expect(!model.textView.isAutomaticTextReplacementEnabled)
        #expect(model.textView.allowsUndo)
        #expect(!model.textView.isRichText)
    }
}
