import AppKit
import SwiftUI

/// SwiftUI's .help() does not reliably surface tooltips for toolbar items,
/// so this attaches a real AppKit tooltip: an invisible NSView behind the
/// content whose tool-tip tracking area (pure geometry, no hit-testing)
/// shows the standard system tooltip without intercepting clicks.
private struct NativeTooltip: NSViewRepresentable {
    let text: String

    final class TipView: NSView {
        // Never steal clicks from the SwiftUI control in front.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = TipView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    /// Shows a native macOS tooltip when the mouse hovers this view.
    public func nativeTooltip(_ text: String) -> some View {
        background(NativeTooltip(text: text))
    }
}
