import AppKit
import SwiftUI

/// Printing is routed to the active document window through the focused
/// scene, the same way the View menu reaches its view mode.
public struct DocumentPrintAction {
    let perform: () -> Void

    public init(perform: @escaping () -> Void) {
        self.perform = perform
    }
}

public struct DocumentPrintKey: FocusedValueKey {
    public typealias Value = DocumentPrintAction
}

extension FocusedValues {
    public var documentPrint: DocumentPrintAction? {
        get { self[DocumentPrintKey.self] }
        set { self[DocumentPrintKey.self] = newValue }
    }
}

/// Replaces the stock (inert) File ▸ Page Setup… / Print… items with ones
/// that print the rendered document of the frontmost tab.
public struct PrintCommands: Commands {
    @FocusedValue(\.documentPrint) private var printAction

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") {
                NSApp.runPageLayout(nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Print…") {
                printAction?.perform()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(printAction == nil)
        }
    }
}
