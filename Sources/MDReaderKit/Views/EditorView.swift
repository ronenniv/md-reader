import AppKit
import SwiftUI

/// Owns the NSTextView so it survives view-mode switches (undo stack,
/// selection, and scroll position stay intact).
@MainActor
public final class EditorModel: ObservableObject {
    public let scrollView: NSScrollView
    public let textView: NSTextView
    let highlighter = MarkdownHighlighter()

    /// True while text is being pushed in from SwiftUI so the delegate does
    /// not echo it back into the binding.
    private(set) var isApplyingExternalUpdate = false

    private var highlightTask: Task<Void, Never>?
    private var cachedLineIndex: LineIndex?

    public init() {
        let sv = NSTextView.scrollableTextView()
        scrollView = sv
        // scrollableTextView() always installs an NSTextView document view.
        textView = sv.documentView as! NSTextView
        configure()
    }

    private func configure() {
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = MarkdownHighlighter.baseFont
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 24, height: 16)
        textView.defaultParagraphStyle = MarkdownHighlighter.paragraphStyle
        textView.typingAttributes = [
            .font: MarkdownHighlighter.baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: MarkdownHighlighter.paragraphStyle,
        ]
        // File drags must fall through to the SwiftUI dropDestination that
        // opens new tabs, instead of pasting a path into the text.
        textView.registerForDraggedTypes(textView.registeredDraggedTypes.filter { $0 != .fileURL })
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    var lineIndex: LineIndex {
        if let cachedLineIndex { return cachedLineIndex }
        let index = LineIndex(text: textView.string)
        cachedLineIndex = index
        return index
    }

    func invalidateLineIndex() {
        cachedLineIndex = nil
    }

    /// Pushes text arriving from SwiftUI (open, external reload, undo of a
    /// programmatic change) into the text view, preserving the selection.
    public func applyExternalText(_ text: String) {
        guard textView.string != text else { return }
        isApplyingExternalUpdate = true
        let selections = textView.selectedRanges
        textView.string = text
        let length = (text as NSString).length
        textView.selectedRanges = selections.map { value in
            let r = value.rangeValue
            let location = min(r.location, length)
            return NSValue(range: NSRange(location: location, length: min(r.length, length - location)))
        }
        isApplyingExternalUpdate = false
        invalidateLineIndex()
        highlightNow()
    }

    func scheduleHighlight() {
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.highlightNow()
        }
    }

    public func highlightNow() {
        guard let storage = textView.textStorage else { return }
        highlighter.highlight(storage)
    }

    /// Scrolls so the given fractional 0-based line sits at the top.
    public func scroll(toFractionalLine fractionalLine: Double) {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        let line = max(0, Int(fractionalLine))
        let fraction = fractionalLine - Double(line)
        let index = lineIndex
        let start = index.characterOffset(forLine: line)
        let nextStart = line + 1 < index.lineCount
            ? index.characterOffset(forLine: line + 1)
            : (textView.string as NSString).length
        let charRange = NSRange(location: start, length: max(0, nextStart - start))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        let y = rect.minY + rect.height * fraction + textView.textContainerInset.height
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, y - 16)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// The fractional 0-based line currently at the top of the visible area.
    func topFractionalLine() -> Double {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return 0 }
        let visibleTop = max(0, scrollView.contentView.bounds.origin.y - textView.textContainerInset.height + 16)
        let glyph = layoutManager.glyphIndex(for: CGPoint(x: 4, y: visibleTop), in: container)
        let char = layoutManager.characterIndexForGlyph(at: glyph)
        let index = lineIndex
        let line = index.line(forCharacter: char)
        let start = index.characterOffset(forLine: line)
        let nextStart = line + 1 < index.lineCount
            ? index.characterOffset(forLine: line + 1)
            : (textView.string as NSString).length
        let charRange = NSRange(location: start, length: max(1, nextStart - start))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        let fraction = rect.height > 0 ? min(1, max(0, (visibleTop - rect.minY) / rect.height)) : 0
        return Double(line) + Double(fraction)
    }
}

public struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let model: EditorModel
    let arbiter: SyncArbiter?
    var onSelectionChange: ((Int, Int) -> Void)?
    var onScroll: ((Double) -> Void)?

    public init(
        text: Binding<String>,
        model: EditorModel,
        arbiter: SyncArbiter? = nil,
        onSelectionChange: ((Int, Int) -> Void)? = nil,
        onScroll: ((Double) -> Void)? = nil
    ) {
        _text = text
        self.model = model
        self.arbiter = arbiter
        self.onSelectionChange = onSelectionChange
        self.onScroll = onScroll
    }

    public func makeNSView(context: Context) -> NSScrollView {
        model.textView.delegate = context.coordinator
        context.coordinator.installScrollObserver(on: model.scrollView)
        model.applyExternalText(text)
        return model.scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        model.applyExternalText(text)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        private var scrollObserver: NSObjectProtocol?
        private var pendingScrollWork: DispatchWorkItem?

        init(_ parent: EditorView) {
            self.parent = parent
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard !parent.model.isApplyingExternalUpdate else { return }
            parent.model.invalidateLineIndex()
            parent.text = parent.model.textView.string
            parent.model.scheduleHighlight()
            reportSelection()
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            reportSelection()
        }

        private func reportSelection() {
            guard let callback = parent.onSelectionChange else { return }
            let location = parent.model.textView.selectedRange().location
            let index = parent.model.lineIndex
            let line = index.line(forCharacter: location)
            let column = location - index.characterOffset(forLine: line)
            callback(line + 1, column + 1)
        }

        func installScrollObserver(on scrollView: NSScrollView) {
            guard scrollObserver == nil else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleScrollReport()
                }
            }
        }

        private func scheduleScrollReport() {
            guard parent.onScroll != nil else { return }
            pendingScrollWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.reportScroll()
            }
            pendingScrollWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
        }

        private func reportScroll() {
            guard let onScroll = parent.onScroll else { return }
            if let arbiter = parent.arbiter, !arbiter.shouldPropagate(from: .editor) { return }
            onScroll(parent.model.topFractionalLine())
        }
    }
}
