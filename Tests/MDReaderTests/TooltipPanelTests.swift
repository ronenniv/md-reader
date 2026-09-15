import AppKit
import Testing

@testable import MDReaderKit

/// Regression guard for the 2026-09-07 field crashes (v1.0.3, v1.0.4): an
/// NSHostingView inside the tiny tooltip panel tripped AppKit's layout-loop
/// detector during the window's constraints pass. The panel must stay pure
/// AppKit with frame-based layout so that pass never runs.
@MainActor
@Suite struct TooltipPanelTests {
    private func allViews(under view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(allViews(under:))
    }

    @Test func panelHostsNoSwiftUIAndUsesNoAutoLayout() {
        let tooltip = TooltipPanel.shared
        tooltip.show(text: "All changes are saved", near: NSPoint(x: 200, y: 200))
        defer { tooltip.hide() }

        let content = try? #require(tooltip.panel.contentView)
        guard let content else { return }
        let views = allViews(under: content)
        #expect(!views.isEmpty)
        for view in views {
            let className = NSStringFromClass(type(of: view))
            #expect(!className.contains("NSHostingView"), "SwiftUI hosting view in tooltip: \(className)")
            #expect(view.translatesAutoresizingMaskIntoConstraints, "\(className) opted into Auto Layout")
            #expect(view.constraints.isEmpty, "\(className) carries constraints")
        }
        #expect(tooltip.panel.frame.width > 0 && tooltip.panel.frame.height > 0)
    }

    @Test func resizesToEachText() {
        let tooltip = TooltipPanel.shared
        tooltip.show(text: "Saved", near: .zero)
        let short = tooltip.panel.frame.size
        tooltip.show(text: "The document has changes not yet saved to disk (⌘S)", near: .zero)
        let long = tooltip.panel.frame.size
        tooltip.hide()
        #expect(long.width > short.width)
        #expect(long.height == short.height)
    }
}
