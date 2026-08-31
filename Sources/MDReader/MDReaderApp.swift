import MDReaderKit
import SwiftUI

@main
struct MDReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
