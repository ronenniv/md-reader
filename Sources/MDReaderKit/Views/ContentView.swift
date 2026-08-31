import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    // Single-pane by default: Reader for existing files, Source for new
    // documents (set in setUp). Split is opt-in via toolbar/⌘3.
    @State private var viewMode: ViewMode = .reader
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
            // nativeTooltip attaches real AppKit tooltips; SwiftUI's .help()
            // does not reliably show them for toolbar items.
            ToolbarItem {
                Button(action: openAction) {
                    Label("Open", systemImage: "folder")
                        .nativeTooltip("Open a markdown file (⌘O)")
                }
            }
            ToolbarItem {
                Button(action: saveAction) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .nativeTooltip("Save changes (⌘S)")
                }
                .disabled(!isDirty)
            }
            ToolbarItem {
                Button(action: saveAsAction) {
                    Label("Save As", systemImage: "square.and.arrow.down.on.square")
                        .nativeTooltip("Save a copy under a new name (⇧⌘S)")
                }
            }
            ToolbarItem {
                Button(action: exportPDF) {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                        .nativeTooltip("Export the rendered document as PDF")
                }
            }
            ToolbarItem {
                Picker("View Mode", selection: $viewMode) {
                    ForEach([ViewMode.source, .split, .reader]) { mode in
                        Image(systemName: mode.symbolName)
                            .help("\(mode.title) (\(mode.shortcutHint))")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .nativeTooltip("View mode — Source ⌘1, Reader ⌘2, Split ⌘3")
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
        .onChange(of: viewMode) { _, newMode in
            previewModel.syncEnabled = newMode == .split
            if newMode == .split {
                // Equal panes on every entry into Split, preview aligned to
                // the editor's current position.
                splitFraction = 0.5
                arbiter.noteProgrammaticScroll(on: .preview)
                previewModel.scroll(toFractionalLine: editorModel.topFractionalLine())
            }
        }
        .onChange(of: document.text) { _, newText in
            wordCount = TextMetrics.wordCount(of: newText)
        }
    }

    /// Fraction of the width given to the editor in Split mode; reset to an
    /// even 50/50 every time Split is entered, draggable afterwards.
    @State private var splitFraction: CGFloat = 0.5
    @State private var isDraggingDivider = false

    private var panes: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if viewMode != .reader {
                    editorPane
                        .frame(width: paneWidths(total: geometry.size.width).editor)
                }
                if viewMode == .split {
                    splitDivider(total: geometry.size.width)
                }
                if viewMode != .source {
                    PreviewView(model: previewModel, text: document.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .coordinateSpace(name: "panes")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paneWidths(total: CGFloat) -> (editor: CGFloat?, minPane: CGFloat) {
        guard viewMode == .split else { return (nil, 0) }  // single pane fills
        let minPane: CGFloat = min(250, total / 2)
        let editor = min(max(total * splitFraction, minPane), total - minPane)
        return (editor, minPane)
    }

    private func splitDivider(total: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("panes"))
                    .onChanged { value in
                        isDraggingDivider = true
                        let minPane = paneWidths(total: total).minPane
                        let x = min(max(value.location.x, minPane), total - minPane)
                        splitFraction = x / total
                    }
                    .onEnded { _ in isDraggingDivider = false }
            )
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
            // No scroll callback outside Split: the coordinator then skips
            // all scroll computation entirely.
            onScroll: viewMode != .split ? nil : { fractionalLine in
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
        // New/empty documents open in Source (you can't type in Reader);
        // existing files open in Reader.
        if document.text.isEmpty && fileURL == nil {
            viewMode = .source
        }
        previewModel.syncEnabled = viewMode == .split
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

    /// Unsaved changes exist (untitled documents always count as unsaved).
    private var isDirty: Bool {
        guard fileURL != nil else { return true }
        return document.text != (lastKnownDiskText ?? document.text)
    }

    // Open/Save/Save As go through the responder chain, which DocumentGroup
    // bridges to the standard document machinery (same as ⌘O/⌘S/⇧⌘S). Each
    // has a manual fallback in case a future macOS stops bridging them.
    private func openAction() {
        if NSApp.sendAction(NSSelectorFromString("openDocument:"), to: nil, from: nil) { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [MarkdownDocument.markdownType, .plainText]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        Task {
            for url in panel.urls {
                try? await openDocument(at: url)
            }
        }
    }

    private func saveAction() {
        if NSApp.sendAction(NSSelectorFromString("saveDocument:"), to: nil, from: nil) { return }
        if let url = fileURL {
            try? document.data().write(to: url)
        } else {
            saveAsAction()
        }
    }

    private func saveAsAction() {
        if NSApp.sendAction(NSSelectorFromString("saveDocumentAs:"), to: nil, from: nil) { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [MarkdownDocument.markdownType]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? document.data().write(to: url)
        Task { try? await openDocument(at: url) }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue =
            (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".pdf"
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let text = document.text
            Task { await performPDFExport(of: text, to: url) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    @MainActor
    private func performPDFExport(of text: String, to url: URL) async {
        do {
            let data = try await previewModel.pdfData(for: text)
            try data.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "PDF export failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
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
