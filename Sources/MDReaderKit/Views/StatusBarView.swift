import SwiftUI

public enum TextMetrics {
    public static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    public static func readingMinutes(forWordCount count: Int) -> Int {
        max(1, Int((Double(count) / 200.0).rounded(.up)))
    }
}

/// Whether the document matches what's on disk.
public enum DocumentSaveState: Equatable, Sendable {
    /// Untitled — never written to disk.
    case unsaved
    /// File-backed with unsaved changes.
    case edited
    /// Matches the file on disk.
    case saved

    public static func resolve(hasFile: Bool, isDirty: Bool) -> DocumentSaveState {
        guard hasFile else { return .unsaved }
        return isDirty ? .edited : .saved
    }

    var label: String {
        switch self {
        case .unsaved: return "Not Saved"
        case .edited: return "Edited"
        case .saved: return "Saved"
        }
    }

    var dotColor: Color {
        switch self {
        case .unsaved, .edited: return .orange
        case .saved: return .green.opacity(0.8)
        }
    }
}

public struct StatusBarView: View {
    let line: Int
    let column: Int
    let wordCount: Int
    let saveState: DocumentSaveState

    public init(line: Int, column: Int, wordCount: Int, saveState: DocumentSaveState) {
        self.line = line
        self.column = column
        self.wordCount = wordCount
        self.saveState = saveState
    }

    public var body: some View {
        // No animation and fixed widths on purpose: state/label changes must
        // never alter this view's measured size. A width change here feeds
        // back into the window's min-size computation, and combined with an
        // in-flight animation it can invalidate the SwiftUI graph during
        // AppKit's constraints pass — an NSException that killed the app in
        // the field (v1.0.3 crash, 2026-09-07).
        HStack(spacing: 12) {
            Text("Ln \(line), Col \(column)")
                .monospacedDigit()
            HStack(spacing: 4) {
                Circle()
                    .fill(saveState.dotColor)
                    .frame(width: 6, height: 6)
                Text(saveState.label)
                Spacer(minLength: 0)
            }
            .frame(width: 84)
            .nativeTooltip(
                saveState == .saved
                    ? "All changes are saved"
                    : "The document has changes not yet saved to disk (⌘S)")
            Spacer()
            Text(summary)
                .monospacedDigit()
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
