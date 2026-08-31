import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var viewMode: ViewMode = .split
    @StateObject private var editorModel = EditorModel()
    @StateObject private var previewModel = PreviewModel()
    @StateObject private var fileWatcher = FileWatcher()
    @State private var arbiter = SyncArbiter()
    @State private var cursorLine = 1
    @State private var cursorColumn = 1
    @State private var wordCount = 0
    @State private var lastKnownDiskText: String?
    @State private var pendingDiskText: String?
    @Environment(\.openDocument) private var openDocument

    public init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            if pendingDiskText != nil {
                ReloadBanner(
                    onReload: reloadFromDisk,
                    onKeep: { pendingDiskText = nil }
                )
            }
            panes
            StatusBarView(line: cursorLine, column: cursorColumn, wordCount: wordCount)
        }
        .toolbar {
            ToolbarItem {
                Picker("View Mode", selection: $viewMode) {
                    ForEach([ViewMode.source, .split, .reader]) { mode in
                        Image(systemName: mode.symbolName)
                            .help("\(mode.title) (\(mode.shortcutHint))")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .focusedSceneValue(\.viewMode, $viewMode)
        .background(WindowAccessor())
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
        .onAppear(perform: setUp)
        .onChange(of: fileURL) { _, newURL in
            rewatch(newURL)
        }
        .onChange(of: document.text) { _, newText in
            wordCount = TextMetrics.wordCount(of: newText)
        }
    }

    private var panes: some View {
        HSplitView {
            if viewMode != .reader {
                editorPane
                    .frame(minWidth: 250, idealWidth: 600, maxWidth: .infinity,
                           maxHeight: .infinity)
            }
            if viewMode != .source {
                PreviewView(model: previewModel, text: document.text)
                    .frame(minWidth: 250, idealWidth: 600, maxWidth: .infinity,
                           maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorPane: some View {
        EditorView(
            text: $document.text,
            model: editorModel,
            arbiter: arbiter,
            onSelectionChange: { line, column in
                cursorLine = line
                cursorColumn = column
            },
            onScroll: { fractionalLine in
                guard viewMode == .split else { return }
                arbiter.noteProgrammaticScroll(on: .preview)
                previewModel.scroll(toFractionalLine: fractionalLine)
            }
        )
        .overlay(alignment: .topLeading) {
            if document.text.isEmpty {
                Text("# Start writing…")
                    .font(.system(size: MarkdownHighlighter.baseFontSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 29)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
        }
    }

    private func setUp() {
        wordCount = TextMetrics.wordCount(of: document.text)
        previewModel.onScroll = { fractionalLine in
            guard viewMode == .split else { return }
            guard arbiter.shouldPropagate(from: .preview) else { return }
            arbiter.noteProgrammaticScroll(on: .editor)
            editorModel.scroll(toFractionalLine: fractionalLine)
        }
        fileWatcher.onChange = {
            handleExternalChange()
        }
        rewatch(fileURL)
    }

    private func rewatch(_ url: URL?) {
        pendingDiskText = nil
        if let url {
            lastKnownDiskText = document.text
            previewModel.documentDirectory = url.deletingLastPathComponent()
            fileWatcher.watch(url)
        } else {
            fileWatcher.stop()
            previewModel.documentDirectory = nil
        }
    }

    private func handleExternalChange() {
        guard let url = fileWatcher.url, let data = try? Data(contentsOf: url) else { return }
        guard let disk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return }
        let action = ExternalChangeResolver.resolve(
            disk: disk,
            lastKnownDisk: lastKnownDiskText ?? document.text,
            editor: document.text
        )
        switch action {
        case .ignore:
            break
        case .adoptAsSaved:
            lastKnownDiskText = disk
        case .reloadSilently:
            lastKnownDiskText = disk
            document.text = disk
        case .conflict:
            pendingDiskText = disk
        }
    }

    private func reloadFromDisk() {
        if let text = pendingDiskText {
            document.text = text
            lastKnownDiskText = text
        }
        pendingDiskText = nil
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
        let markdownURLs = urls.filter { markdownExtensions.contains($0.pathExtension.lowercased()) }
        guard !markdownURLs.isEmpty else { return false }
        Task {
            for url in markdownURLs {
                try? await openDocument(at: url)
            }
        }
        return true
    }
}
