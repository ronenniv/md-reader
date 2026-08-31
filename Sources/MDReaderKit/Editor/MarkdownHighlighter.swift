import AppKit

/// Lightweight line-based markdown syntax highlighter for the source editor.
/// Semantic system colors keep it correct in both light and dark mode; the
/// delimiter characters themselves recede so the content pops.
public struct MarkdownHighlighter {
    public static let baseFontSize: CGFloat = 13

    public static let baseFont = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
    public static let boldFont = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .bold)
    public static let headingFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)

    public static let italicFont: NSFont = {
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: baseFontSize) ?? baseFont
    }()

    public static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.35
        return style
    }()

    static let codeBackground = NSColor.labelColor.withAlphaComponent(0.07)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a failure is a programmer error.
        try! NSRegularExpression(pattern: pattern)
    }

    private static let heading = regex(#"^(#{1,6})[ \t]+"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = regex(#"(?<![\w*_])(\*|_)(?![\s*_])([^*_\n]+?)(?<![\s*_])\1(?![\w*_])"#)
    private static let codeSpan = regex(#"`[^`\n]+`"#)
    private static let link = regex(#"\[([^\]]*)\]\(([^)\s]+)\)"#)
    private static let blockquote = regex(#"^[ \t]*>"#)
    private static let listMarker = regex(#"^[ \t]*(?:[-*+]|\d{1,9}\.)[ \t]"#)
    private static let taskBox = regex(#"^[ \t]*[-*+][ \t]+\[( |x|X)\]"#)
    private static let fence = regex(#"^[ \t]*(```|~~~)"#)

    public init() {}

    public func highlight(_ storage: NSTextStorage) {
        let text = storage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: fullRange)
        storage.addAttribute(.font, value: Self.baseFont, range: fullRange)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        storage.addAttribute(.paragraphStyle, value: Self.paragraphStyle, range: fullRange)

        var inFence = false
        var lineRanges: [NSRange] = []
        text.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            lineRanges.append(lineRange)
        }

        for lineRange in lineRanges {
            if Self.fence.firstMatch(in: storage.string, range: lineRange) != nil {
                inFence.toggle()
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lineRange)
                continue
            }
            if inFence {
                storage.addAttribute(.backgroundColor, value: Self.codeBackground, range: lineRange)
                continue
            }
            highlightLine(storage, in: lineRange)
        }

        storage.endEditing()
    }

    private func highlightLine(_ storage: NSTextStorage, in lineRange: NSRange) {
        let string = storage.string

        if let m = Self.blockquote.firstMatch(in: string, range: lineRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range)
        }

        if let m = Self.listMarker.firstMatch(in: string, range: lineRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range)
        }

        if let m = Self.taskBox.firstMatch(in: string, range: lineRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range)
            storage.addAttribute(.font, value: Self.boldFont, range: m.range)
        }

        if let m = Self.heading.firstMatch(in: string, range: lineRange) {
            let level = m.range(at: 1).length
            let font = level <= 2 ? Self.headingFont : Self.boldFont
            storage.addAttribute(.font, value: font, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range(at: 1))
        }

        for m in Self.bold.matches(in: string, range: lineRange) {
            storage.addAttribute(.font, value: Self.boldFont, range: m.range(at: 2))
            let d = m.range(at: 1).length
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                 range: NSRange(location: m.range.location, length: d))
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                 range: NSRange(location: m.range.location + m.range.length - d, length: d))
        }

        for m in Self.italic.matches(in: string, range: lineRange) {
            storage.addAttribute(.font, value: Self.italicFont, range: m.range(at: 2))
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                 range: NSRange(location: m.range.location, length: 1))
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                 range: NSRange(location: m.range.location + m.range.length - 1, length: 1))
        }

        for m in Self.link.matches(in: string, range: lineRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range(at: 2))
        }

        for m in Self.codeSpan.matches(in: string, range: lineRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: m.range)
            storage.addAttribute(.backgroundColor, value: Self.codeBackground, range: m.range)
            storage.addAttribute(.font, value: Self.baseFont, range: m.range)
        }
    }
}
