import Foundation

/// Caches UTF-16 offsets of line starts for fast character ↔ line mapping,
/// used by the status bar and scroll sync.
public struct LineIndex {
    public private(set) var lineStarts: [Int]

    public init(text: String) {
        let ns = text as NSString
        var starts = [0]
        var index = 0
        while index < ns.length {
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: index, length: 0))
            // A terminator means another line starts at lineEnd (even at EOF,
            // where the trailing newline creates a final empty line).
            if contentsEnd != lineEnd {
                starts.append(lineEnd)
            }
            if lineEnd <= index { break }
            index = lineEnd
        }
        lineStarts = starts
    }

    public var lineCount: Int { lineStarts.count }

    /// 0-based line containing the given UTF-16 offset.
    public func line(forCharacter offset: Int) -> Int {
        var lo = 0
        var hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// UTF-16 offset of the start of a 0-based line (clamped to valid lines).
    public func characterOffset(forLine line: Int) -> Int {
        lineStarts[max(0, min(line, lineStarts.count - 1))]
    }
}
