import SwiftUI

public enum ViewMode: String, CaseIterable, Identifiable, Sendable {
    case source
    case split
    case reader

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .source: return "Source"
        case .split: return "Split"
        case .reader: return "Reader"
        }
    }

    public var symbolName: String {
        switch self {
        case .source: return "chevron.left.forwardslash.chevron.right"
        case .split: return "rectangle.split.2x1"
        case .reader: return "doc.richtext"
        }
    }

    public var shortcutHint: String {
        switch self {
        case .source: return "⌘1"
        case .reader: return "⌘2"
        case .split: return "⌘3"
        }
    }
}

public struct ViewModeFocusedKey: FocusedValueKey {
    public typealias Value = Binding<ViewMode>
}

extension FocusedValues {
    public var viewMode: Binding<ViewMode>? {
        get { self[ViewModeFocusedKey.self] }
        set { self[ViewModeFocusedKey.self] = newValue }
    }
}

/// Adds Source/Reader/Split to the standard View menu, routed to the
/// active tab via the focused scene.
public struct ViewModeCommands: Commands {
    @FocusedBinding(\.viewMode) private var viewMode: ViewMode?

    public init() {}

    public var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Source") { viewMode = .source }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(viewMode == nil)
            Button("Reader") { viewMode = .reader }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(viewMode == nil)
            Button("Split") { viewMode = .split }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(viewMode == nil)
            Divider()
        }
    }
}
