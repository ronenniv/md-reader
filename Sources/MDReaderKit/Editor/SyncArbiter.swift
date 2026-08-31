import Foundation

/// Prevents feedback loops in two-way scroll sync: the side the user is
/// actively scrolling owns the sync for a short window, and each side's
/// programmatic scrolls are ignored so they don't echo back.
public final class SyncArbiter {
    public enum Side: Sendable {
        case editor
        case preview
    }

    /// Injectable clock for tests.
    public var now: () -> Date = { Date() }
    public var ownershipWindow: TimeInterval = 0.25
    public var programmaticWindow: TimeInterval = 0.15

    private var owner: Side?
    private var ownerUntil = Date.distantPast
    private var ignoreEditorUntil = Date.distantPast
    private var ignorePreviewUntil = Date.distantPast

    public init() {}

    /// Call right before scrolling `side` programmatically so its resulting
    /// scroll events are dropped instead of echoed back.
    public func noteProgrammaticScroll(on side: Side) {
        let until = now().addingTimeInterval(programmaticWindow)
        switch side {
        case .editor: ignoreEditorUntil = until
        case .preview: ignorePreviewUntil = until
        }
    }

    /// A scroll event fired on `side`; returns true if it should propagate
    /// to the other side.
    public func shouldPropagate(from side: Side) -> Bool {
        let t = now()
        let ignoreUntil = side == .editor ? ignoreEditorUntil : ignorePreviewUntil
        if t < ignoreUntil { return false }
        if let owner, owner != side, t < ownerUntil { return false }
        owner = side
        ownerUntil = t.addingTimeInterval(ownershipWindow)
        return true
    }
}
