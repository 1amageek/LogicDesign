import LogicIR
import LogicKernelCore

public struct SystemVerilogSourceText: Sendable {
    private final class Storage: Sendable {
        let bytes: [UInt8]
        let segments: [SystemVerilogSourceSegment]
        let runStarts: [Int]
        let terminalOrigin: LogicKernelSourceRange
        init(bytes: consuming [UInt8], segments: consuming [SystemVerilogSourceSegment],
             runStarts: consuming [Int], terminalOrigin: LogicKernelSourceRange) {
            self.bytes = bytes; self.segments = segments; self.runStarts = runStarts
            self.terminalOrigin = terminalOrigin
        }
    }

    public let root: LogicSourceDocument
    private let storage: Storage?
    public var byteCount: Int { storage?.bytes.count ?? root.byteCount }

    public init(_ root: borrowing LogicSourceDocument) { self.root = copy root; storage = nil }

    @available(macOS 26.0, *)
    package init(root: borrowing LogicSourceDocument, bytes: consuming [UInt8],
                 segments: consuming [SystemVerilogSourceSegment], terminalOrigin: LogicKernelSourceRange,
                 context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.checkpoint()
        guard terminalOrigin.byteRange.isEmpty else { throw .invalidInput("Terminal source origin must be a point") }
        let segmentBytes = UInt64(segments.count).multipliedReportingOverflow(
            by: UInt64(MemoryLayout<SystemVerilogSourceSegment>.stride + MemoryLayout<Int>.stride))
        let total = segmentBytes.partialValue.addingReportingOverflow(UInt64(bytes.count))
        guard !segmentBytes.overflow, !total.overflow else { throw .invalidInput("Source text storage overflow") }
        try context.require(.edges, amount: UInt64(segments.count))
        try context.charge(.expansion, amount: UInt64(bytes.count))
        let receipt = try context.reserveStorage(byteCount: total.partialValue)
        var runs: [Int] = []
        do throws(LogicKernelError) {
            try LogicSourceDocument.validateUTF8(bytes, context: &context)
            runs.reserveCapacity(segments.count)
            var end = 0
            for index in segments.indices {
                try context.charge(.workUnits)
                let segment = segments[index]
                guard segment.textRange.lowerBound == end, !segment.textRange.isEmpty,
                      segment.textRange.upperBound <= bytes.count, !segment.origin.byteRange.isEmpty,
                      segment.document.artifactID == segment.origin.artifactID else {
                    throw .invalidInput("Source segments must cover text without gaps or overlaps")
                }
                if segment.isExact, UInt64(segment.textRange.count) != (segment.origin.byteRange.upperBound - segment.origin.byteRange.lowerBound) {
                    throw .invalidInput("Exact source segment has unequal text and artifact lengths")
                }
                var start = index
                if index > 0 {
                    let previous = segments[index - 1]
                    if previous.origin.artifactID == segment.origin.artifactID,
                       previous.origin.byteRange.upperBound <= segment.origin.byteRange.lowerBound {
                        start = runs[index - 1]
                    }
                }
                runs.append(start); end = segment.textRange.upperBound
            }
            guard end == bytes.count else { throw .invalidInput("Source segments leave uncovered text") }
            for index in segments.indices where segments[index].isExact {
                let segment = segments[index]
                guard let start = Int(exactly: segment.origin.byteRange.lowerBound) else {
                    throw .invalidInput("Source origin offset is unrepresentable")
                }
                try segment.document.withBytes { (original: borrowing Span<UInt8>) throws(LogicKernelError) in
                    for offset in 0..<segment.textRange.count {
                        try context.charge(.workUnits)
                        guard bytes[segment.textRange.lowerBound + offset] == original[start + offset] else {
                            throw .invalidInput("Exact source segment differs from its input artifact bytes")
                        }
                    }
                }
            }
        } catch { try context.releaseStorage(receipt); throw error }
        self.root = copy root
        storage = Storage(bytes: bytes, segments: segments, runStarts: runs, terminalOrigin: terminalOrigin)
    }

    @available(macOS 26.0, *)
    public borrowing func withBytes<Result, Failure: Error>(
        _ body: (borrowing Span<UInt8>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        guard let owner = storage else { return try root.withBytes(body) }
        let bytes = owner.bytes
        defer { withExtendedLifetime(owner) {} }
        return try body(bytes.isEmpty ? Span() : bytes.span)
    }

    public borrowing func origin(for range: Range<Int>) throws(LogicKernelError) -> LogicKernelSourceRange {
        guard range.lowerBound >= 0, range.upperBound <= byteCount else {
            throw .invalidInput("Source text range is outside its owner")
        }
        guard let owner = storage else {
            return try LogicKernelSourceRange(artifactID: root.artifactID,
                byteRange: UInt64(range.lowerBound)..<UInt64(range.upperBound))
        }
        if range.lowerBound == owner.bytes.count { return owner.terminalOrigin }
        let first = Self.segment(at: range.lowerBound, owner: owner)
        let last = range.isEmpty ? first : Self.segment(at: range.upperBound - 1, owner: owner)
        let leading = owner.segments[first]
        let begin = leading.isExact
            ? leading.origin.byteRange.lowerBound + UInt64(range.lowerBound - leading.textRange.lowerBound)
            : leading.origin.byteRange.lowerBound
        let ending: UInt64
        if owner.runStarts[last] <= first {
            let trailing = owner.segments[last]
            ending = trailing.isExact
                ? trailing.origin.byteRange.lowerBound + UInt64(range.upperBound - trailing.textRange.lowerBound)
                : trailing.origin.byteRange.upperBound
        } else {
            ending = leading.isExact
                ? leading.origin.byteRange.lowerBound + UInt64(min(range.upperBound, leading.textRange.upperBound) - leading.textRange.lowerBound)
                : leading.origin.byteRange.upperBound
        }
        return try LogicKernelSourceRange(artifactID: leading.origin.artifactID, byteRange: begin..<ending)
    }

    package borrowing func forEachOrigin(in range: Range<Int>,
        _ body: (borrowing SystemVerilogSourceSegment) throws(LogicKernelError) -> Void
    ) throws(LogicKernelError) {
        guard range.lowerBound >= 0, range.upperBound <= byteCount else {
            throw .invalidInput("Source text segment range is outside its owner")
        }
        guard !range.isEmpty else { return }
        guard let owner = storage else {
            try body(SystemVerilogSourceSegment(textRange: range, document: root,
                origin: origin(for: range), isExact: true))
            return
        }
        let first = Self.segment(at: range.lowerBound, owner: owner)
        let last = Self.segment(at: range.upperBound - 1, owner: owner)
        for index in first...last {
            let segment = owner.segments[index]
            let clipped = max(range.lowerBound, segment.textRange.lowerBound)..<min(range.upperBound, segment.textRange.upperBound)
            let projected: LogicKernelSourceRange
            if segment.isExact {
                let begin = segment.origin.byteRange.lowerBound + UInt64(clipped.lowerBound - segment.textRange.lowerBound)
                let end = segment.origin.byteRange.lowerBound + UInt64(clipped.upperBound - segment.textRange.lowerBound)
                projected = try LogicKernelSourceRange(artifactID: segment.origin.artifactID, byteRange: begin..<end)
            } else { projected = segment.origin }
            try body(SystemVerilogSourceSegment(textRange: clipped, document: segment.document,
                origin: projected, isExact: segment.isExact))
        }
    }

    private static func segment(at position: Int, owner: Storage) -> Int {
        var low = 0; var high = owner.segments.count
        while low < high {
            let middle = low + (high - low) / 2
            if owner.segments[middle].textRange.upperBound <= position { low = middle + 1 }
            else { high = middle }
        }
        return low
    }
}
