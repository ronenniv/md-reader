import AppKit
import SwiftUI

/// Neither SwiftUI's .help() nor plain NSView.toolTip surfaces tooltips for
/// these toolbar items, so this implements tooltips from scratch: a
/// hitTest-transparent NSView with a tracking area detects hover (pure
/// geometry, clicks unaffected) and shows a floating tooltip panel.
private struct NativeTooltip: NSViewRepresentable {
    let text: String

    final class TipView: NSView {
        var text = ""
        private var showTimer: Timer?

        // Never steal clicks from the SwiftUI control in front.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self,
                    userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            showTimer?.invalidate()
            showTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                guard let self, self.window != nil else { return }
                TooltipPanel.shared.show(text: self.text, near: NSEvent.mouseLocation)
            }
        }

        override func mouseExited(with event: NSEvent) {
            showTimer?.invalidate()
            showTimer = nil
            TooltipPanel.shared.hide()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                showTimer?.invalidate()
                showTimer = nil
                TooltipPanel.shared.hide()
            }
        }

        deinit {
            showTimer?.invalidate()
        }
    }

    func makeNSView(context: Context) -> TipView {
        let view = TipView()
        view.text = text
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: TipView, context: Context) {
        nsView.text = text
        nsView.toolTip = text
    }
}

/// A small floating, non-activating panel styled like a system tooltip.
@MainActor
final class TooltipPanel {
    static let shared = TooltipPanel()
    private let panel: NSPanel

    private init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
    }

    func show(text: String, near screenPoint: NSPoint) {
        let content = NSHostingView(rootView: TooltipBubble(text: text))
        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)
        panel.contentView = content
        panel.setContentSize(size)
        // Below-right of the cursor, clamped to the screen.
        var origin = NSPoint(x: screenPoint.x + 10, y: screenPoint.y - size.height - 12)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(screenPoint, $0.frame, false) }) {
            origin.x = min(origin.x, screen.visibleFrame.maxX - size.width - 4)
            origin.y = max(origin.y, screen.visibleFrame.minY + 4)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct TooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

extension View {
    /// Shows a tooltip when the mouse hovers this view for a moment.
    public func nativeTooltip(_ text: String) -> some View {
        background(NativeTooltip(text: text))
    }
}
