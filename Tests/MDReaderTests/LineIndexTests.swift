import Foundation
import Testing

@testable import MDReaderKit

@Suite struct LineIndexTests {
    @Test func empty() {
        let index = LineIndex(text: "")
        #expect(index.lineCount == 1)
        #expect(index.line(forCharacter: 0) == 0)
        #expect(index.characterOffset(forLine: 0) == 0)
    }

    @Test func simpleLines() {
        let index = LineIndex(text: "ab\ncd\nef")
        #expect(index.lineStarts == [0, 3, 6])
        #expect(index.line(forCharacter: 0) == 0)
        #expect(index.line(forCharacter: 2) == 0)
        #expect(index.line(forCharacter: 3) == 1)
        #expect(index.line(forCharacter: 7) == 2)
    }

    @Test func trailingNewlineCreatesFinalLine() {
        let index = LineIndex(text: "ab\n")
        #expect(index.lineStarts == [0, 3])
        #expect(index.line(forCharacter: 3) == 1)
    }

    @Test func emptyLines() {
        let index = LineIndex(text: "a\n\n\nb")
        #expect(index.lineStarts == [0, 2, 3, 4])
        #expect(index.line(forCharacter: 2) == 1)
        #expect(index.line(forCharacter: 4) == 3)
    }

    @Test func unicodeUsesUTF16Offsets() {
        // 👋 is two UTF-16 code units.
        let index = LineIndex(text: "👋\nx")
        #expect(index.lineStarts == [0, 3])
        #expect(index.line(forCharacter: 3) == 1)
    }

    @Test func characterOffsetClamps() {
        let index = LineIndex(text: "a\nb")
        #expect(index.characterOffset(forLine: -5) == 0)
        #expect(index.characterOffset(forLine: 99) == 2)
    }
}

@Suite struct SyncArbiterTests {
    private func makeArbiter() -> (SyncArbiter, (TimeInterval) -> Void) {
        let arbiter = SyncArbiter()
        nonisolated(unsafe) var current = Date(timeIntervalSinceReferenceDate: 1000)
        arbiter.now = { current }
        return (arbiter, { current = current.addingTimeInterval($0) })
    }

    @Test func firstEventPropagates() {
        let (arbiter, _) = makeArbiter()
        #expect(arbiter.shouldPropagate(from: .editor))
    }

    @Test func ownershipBlocksOtherSideWithinWindow() {
        let (arbiter, advance) = makeArbiter()
        #expect(arbiter.shouldPropagate(from: .editor))
        advance(0.1)
        #expect(!arbiter.shouldPropagate(from: .preview))
        advance(0.3)
        #expect(arbiter.shouldPropagate(from: .preview))
    }

    @Test func programmaticScrollEchoIsDropped() {
        let (arbiter, advance) = makeArbiter()
        arbiter.noteProgrammaticScroll(on: .editor)
        advance(0.05)
        #expect(!arbiter.shouldPropagate(from: .editor))
        advance(0.2)
        #expect(arbiter.shouldPropagate(from: .editor))
    }

    @Test func continuousScrollingKeepsOwnership() {
        let (arbiter, advance) = makeArbiter()
        for _ in 0..<10 {
            #expect(arbiter.shouldPropagate(from: .editor))
            advance(0.1)
            #expect(!arbiter.shouldPropagate(from: .preview))
        }
    }
}
