import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
internal struct SystemVerilogTextBuffer: ~Copyable {
    var receipt: LogicStorageReservation
    var storageBytes: UInt64 = 0
    private var bytes = SystemVerilogPreprocessingBuffer<UInt8>()
    private var segments = SystemVerilogPreprocessingBuffer<SystemVerilogSourceSegment>()
    var count: Int { bytes.count }

    init(context: inout LogicKernelContext) throws(LogicKernelError) {
        receipt = try context.reserveStorage(byteCount: 0)
    }

    mutating func appendSeparator(anchor: (LogicSourceDocument, LogicKernelSourceRange),
                                  context: inout LogicKernelContext) throws(LogicKernelError) {
        let next = count.addingReportingOverflow(1)
        guard !next.overflow else { throw .invalidInput("Preprocessing separator count overflow") }
        try context.require(.outputBytes, amount: UInt64(next.partialValue))
        try context.charge(.expansion)
        try bytes.append(10, receipt: &receipt, bytes: &storageBytes, context: &context)
        try appendOrigin(SystemVerilogSourceSegment(textRange: (next.partialValue - 1)..<next.partialValue,
            document: anchor.0, origin: anchor.1, isExact: false), context: &context)
    }

    mutating func append(_ text: borrowing SystemVerilogSourceText, range: Range<Int>,
                         anchor: (LogicSourceDocument, LogicKernelSourceRange)? = nil,
                         context: inout LogicKernelContext) throws(LogicKernelError) {
        guard range.lowerBound >= 0, range.upperBound <= text.byteCount else {
            throw .invalidInput("Preprocessing copy range is outside text")
        }
        guard !range.isEmpty else { return }
        let start = bytes.count
        let end = start.addingReportingOverflow(range.count)
        guard !end.overflow else { throw .invalidInput("Preprocessed text count overflow") }
        try context.require(.outputBytes, amount: UInt64(end.partialValue))
        try context.charge(.expansion, amount: UInt64(range.count))
        try bytes.reserve(end.partialValue, receipt: &receipt, bytes: &storageBytes, context: &context)
        try text.withBytes { (source: borrowing Span<UInt8>) throws(LogicKernelError) in
            for index in range {
                try context.charge(.workUnits)
                try bytes.append(source[index], receipt: &receipt, bytes: &storageBytes, context: &context)
            }
        }
        if let anchor {
            try appendOrigin(SystemVerilogSourceSegment(textRange: start..<end.partialValue,
                document: anchor.0, origin: anchor.1, isExact: false), context: &context)
        } else {
            try text.forEachOrigin(in: range) { (segment: borrowing SystemVerilogSourceSegment) throws(LogicKernelError) in
                let offset = segment.textRange.lowerBound - range.lowerBound
                try appendOrigin(SystemVerilogSourceSegment(textRange: (start + offset)..<(start + offset + segment.textRange.count),
                    document: segment.document, origin: segment.origin, isExact: segment.isExact), context: &context)
            }
        }
    }

    private mutating func appendOrigin(_ segment: SystemVerilogSourceSegment,
                                      context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.charge(.workUnits)
        if segments.count > 0 {
            let last = segments.count - 1; let previous = segments[last]
            let same = previous.document.artifactID == segment.document.artifactID
                && previous.textRange.upperBound == segment.textRange.lowerBound && previous.isExact == segment.isExact
            let adjacent = previous.isExact ? previous.origin.byteRange.upperBound == segment.origin.byteRange.lowerBound
                : previous.origin == segment.origin
            if same && adjacent {
                let origin = try LogicKernelSourceRange(artifactID: previous.origin.artifactID,
                    byteRange: previous.origin.byteRange.lowerBound..<segment.origin.byteRange.upperBound)
                segments[last] = SystemVerilogSourceSegment(textRange: previous.textRange.lowerBound..<segment.textRange.upperBound,
                    document: previous.document, origin: origin, isExact: previous.isExact)
                return
            }
        }
        try segments.append(segment, receipt: &receipt, bytes: &storageBytes, context: &context)
    }

    consuming func finish(root: borrowing LogicSourceDocument, terminalOrigin: LogicKernelSourceRange,
                          context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogSourceText {
        let result: SystemVerilogSourceText
        do throws(LogicKernelError) {
            result = try SystemVerilogSourceText(root: root, bytes: bytes.values, segments: segments.values,
                terminalOrigin: terminalOrigin, context: &context)
        } catch { try context.releaseStorage(receipt); throw error }
        try context.releaseStorage(receipt)
        return result
    }

    consuming func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.releaseStorage(receipt)
    }
}
