import AppKit
import SwiftUI

/// Joins each document window into the native tab group. DocumentGroup opens
/// one window per document; with tabbingMode = .preferred plus an explicit
/// addTabbedWindow fallback, they merge into tabs with the filename on the tab.
public struct WindowAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.adopt(window)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    private static func adopt(_ window: NSWindow) {
        window.tabbingMode = .preferred
        let alreadyTabbed = (window.tabbedWindows?.count ?? 0) > 1
        guard !alreadyTabbed else { return }
        if let host = NSApp.windows.first(where: {
            $0 !== window && $0.isVisible && $0.tabbingMode == .preferred
        }) {
            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
