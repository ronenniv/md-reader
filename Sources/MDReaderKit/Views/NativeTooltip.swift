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
                // Scheduled from the main thread, so it fires on the main run loop.
                MainActor.assumeIsolated {
                    guard let self, self.window != nil else { return }
                    TooltipPanel.shared.show(text: self.text, near: NSEvent.mouseLocation)
                }
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
///
/// Pure AppKit with frame-based layout — deliberately no SwiftUI inside.
/// The 2026-09-07 field crashes (v1.0.3 and v1.0.4) came from an
/// NSHostingView here: its updateConstraints pass drives the window's
/// content min/max size from the SwiftUI graph, the graph invalidated
/// itself during that measurement, and a panel this small has so few views
/// that AppKit's layout-loop detector ("more Update Constraints in Window
/// passes than there are views in the window") threw after a couple of
/// rounds — an NSException AppKit turns into a crash regardless of
/// NSApplicationCrashOnExceptions. With no constraints in the window there
/// is no constraints pass to loop.
@MainActor
final class TooltipPanel {
    static let shared = TooltipPanel()

    /// Internal (not private) so tests can assert the panel's view tree.
    let panel: NSPanel
    private let bubble = BubbleView()
    private let label = NSTextField(labelWithString: "")
    private static let padding = NSSize(width: 8, height: 4)

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

        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        // Frame-based on purpose: no Auto Layout means no constraint passes
        // in this window at all.
        label.translatesAutoresizingMaskIntoConstraints = true
        bubble.translatesAutoresizingMaskIntoConstraints = true
        bubble.addSubview(label)
        panel.contentView = bubble
    }

    func show(text: String, near screenPoint: NSPoint) {
        panel.orderOut(nil)
        label.stringValue = text
        label.sizeToFit()
        let pad = Self.padding
        let size = NSSize(
            width: ceil(label.frame.width) + pad.width * 2,
            height: ceil(label.frame.height) + pad.height * 2)
        panel.setContentSize(size)
        label.setFrameOrigin(NSPoint(x: pad.width, y: pad.height))
        bubble.needsDisplay = true
        // Below-right of the cursor, clamped to the screen.
        var origin = NSPoint(x: screenPoint.x + 10, y: screenPoint.y - size.height - 12)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(screenPoint, $0.frame, false) }) {
            origin.x = min(origin.x, screen.visibleFrame.maxX - size.width - 4)
            origin.y = max(origin.y, screen.visibleFrame.minY + 4)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Rounded, hairline-bordered tooltip background. Drawn rather than
/// layer-colored so the semantic colors resolve against the panel's
/// effective appearance (light/dark) at draw time.
private final class BubbleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

extension View {
    /// Shows a tooltip when the mouse hovers this view for a moment.
    public func nativeTooltip(_ text: String) -> some View {
        background(NativeTooltip(text: text))
    }
}
