import SwiftUI

public enum TextMetrics {
    public static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    public static func readingMinutes(forWordCount count: Int) -> Int {
        max(1, Int((Double(count) / 200.0).rounded(.up)))
    }
}

public struct StatusBarView: View {
    let line: Int
    let column: Int
    let wordCount: Int

    public init(line: Int, column: Int, wordCount: Int) {
        self.line = line
        self.column = column
        self.wordCount = wordCount
    }

    public var body: some View {
        HStack {
            Text("Ln \(line), Col \(column)")
            Spacer()
            Text(summary)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var summary: String {
        let words = "\(wordCount) word\(wordCount == 1 ? "" : "s")"
        return "\(words) · ~\(TextMetrics.readingMinutes(forWordCount: wordCount)) min read"
    }
}

public struct ReloadBanner: View {
    let onReload: () -> Void
    let onKeep: () -> Void

    public init(onReload: @escaping () -> Void, onKeep: @escaping () -> Void) {
        self.onReload = onReload
        self.onKeep = onKeep
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("This file was changed on disk.")
            Spacer()
            Button("Reload (discard my edits)", action: onReload)
            Button("Keep Mine", action: onKeep)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}
