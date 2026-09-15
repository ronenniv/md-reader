import MDReaderKit
import SwiftUI

@main
struct MDReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // v1.0.4 wrote NSApplicationCrashOnExceptions=false here hoping
        // AppKit would log-and-continue on layout exceptions. It did not:
        // the v1.0.4 crash went through +[NSApplication _crashOnException:]
        // with the key already set to 0. Remove the stale override from the
        // user's defaults instead of leaving a dead knob behind.
        UserDefaults.standard.removeObject(forKey: "NSApplicationCrashOnExceptions")
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
