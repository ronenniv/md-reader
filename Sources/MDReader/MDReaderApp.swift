import MDReaderKit
import SwiftUI

@main
struct MDReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // SwiftUI registers NSApplicationCrashOnExceptions=YES, turning any
        // AppKit layout exception into a crash that loses unsaved work. A
        // sporadic constraints-reentrancy exception did exactly that in the
        // field; prefer AppKit's legacy log-and-continue behavior. (set()
        // writes the persistent domain, which outranks SwiftUI's
        // registration domain.)
        UserDefaults.standard.set(false, forKey: "NSApplicationCrashOnExceptions")
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { configuration in
            ContentView(document: configuration.$document, fileURL: configuration.fileURL)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            ViewModeCommands()
        }
    }
}
