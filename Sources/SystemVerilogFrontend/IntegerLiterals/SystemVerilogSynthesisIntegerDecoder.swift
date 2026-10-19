import CircuiteFoundation
import LogicIR
import LogicKernelCore

public struct SystemVerilogSynthesisIntegerDecoder: SystemVerilogSynthesisLiteralDecoding {
    private struct Header {
        let width: Int?
        let signed: Bool
        let radix: UInt64
        let digits: Range<Int>
        let digitCount: Int
    }
    public init() {}

    @available(macOS 26.0, *)
    public func decode(_ byteRange: Range<Int>, in source: borrowing LogicSourceDocument,
                       context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogSynthesisLiteral {
        try decode(byteRange, in: SystemVerilogSourceText(source), context: &context)
    }

    @available(macOS 26.0, *)
    package func decode(_ byteRange: Range<Int>, in source: borrowing SystemVerilogSourceText,
                        context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogSynthesisLiteral {
        try context.checkpoint()
        guard byteRange.lowerBound >= 0, byteRange.upperBound <= source.byteCount, !byteRange.isEmpty else {
            throw .invalidInput("Literal range outside source or empty")
        }
        return try source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
            let range = try trim(byteRange, bytes: bytes, context: &context)
            if range.count == 2, bytes[range.lowerBound] == 39 {
                switch bytes[range.lowerBound + 1] {
                case 48: return .fill(false)
                case 49: return .fill(true)
                case 88, 90, 120, 122:
                    throw try failure("SV_SYNTHESIS_XZ_LITERAL", range, source: source)
                default: break
                }
            }
            let header = try parseHeader(range, bytes: bytes, source: source, context: &context)
            if let width = header.width { try context.observeBitWidth(UInt64(width)) }
            let bound = header.digitCount.multipliedReportingOverflow(by: header.radix == 2 ? 1 : header.radix == 8 ? 3 : 4)
            let signedBound = bound.partialValue.addingReportingOverflow(header.radix == 10 && header.signed ? 1 : 0)
            guard !bound.overflow, !signedBound.overflow else { throw try failure("SV_LITERAL_SIZE_OVERFLOW", range, source: source) }
            let capacityWidth = try LogicBitWidth(header.width ?? max(32, signedBound.partialValue))
            let reservation = try context.reserveStorage(byteCount: UInt64(capacityWidth.wordCount) * 8)
            let result: SystemVerilogSynthesisLiteral
            do throws(LogicKernelError) {
                result = try accumulate(header, capacity: capacityWidth, bytes: bytes, context: &context)
            } catch { try context.releaseStorage(reservation); throw error }
            try context.releaseStorage(reservation)
            return result
        }
    }

    @available(macOS 26.0, *)
    private func parseHeader(_ range: Range<Int>, bytes: borrowing Span<UInt8>, source: borrowing SystemVerilogSourceText,
                             context: inout LogicKernelContext) throws(LogicKernelError) -> Header {
        guard !range.isEmpty else { throw try failure("SV_LITERAL_MISSING_DIGITS", range, source: source) }
        var quote: Int?
        for index in range {
            try context.charge(.workUnits)
            if bytes[index] == 39 { quote = index; break }
        }
        var width: Int?
        var signed = true
        var radix: UInt64 = 10
        var start = range.lowerBound
        if let quote {
            let prefix = try trim(range.lowerBound..<quote, bytes: bytes, context: &context)
            if !prefix.isEmpty {
                var size = 0
                guard Self.isDigit(bytes[prefix.lowerBound]) else { throw try failure("SV_LITERAL_INVALID_SIZE", prefix, source: source) }
                for index in prefix {
                    try context.charge(.workUnits)
                    let byte = bytes[index]
                    if byte == 95 { continue }
                    guard Self.isDigit(byte) else { throw try failure("SV_LITERAL_INVALID_SIZE", prefix, source: source) }
                    let product = size.multipliedReportingOverflow(by: 10)
                    let sum = product.partialValue.addingReportingOverflow(Int(byte - 48))
                    guard !product.overflow, !sum.overflow else { throw try failure("SV_LITERAL_SIZE_OVERFLOW", prefix, source: source) }
                    size = sum.partialValue
                }
                guard size > 0 else { throw try failure("SV_LITERAL_INVALID_SIZE", prefix, source: source) }
                width = size
            }
            start = quote + 1; signed = false
            if start < range.upperBound, bytes[start] == 115 || bytes[start] == 83 { signed = true; start += 1 }
            guard start < range.upperBound else { throw try failure("SV_LITERAL_MISSING_BASE", range, source: source) }
            switch bytes[start] {
            case 98, 66: radix = 2
            case 111, 79: radix = 8
            case 100, 68: radix = 10
            case 104, 72: radix = 16
            default: throw try failure("SV_LITERAL_INVALID_BASE", range, source: source)
            }
            start += 1
        }
        let digits = try trim(start..<range.upperBound, bytes: bytes, context: &context)
        guard !digits.isEmpty, bytes[digits.lowerBound] != 95 else { throw try failure("SV_LITERAL_MISSING_DIGITS", digits, source: source) }
        var count = 0
        for index in digits {
            try context.charge(.workUnits)
            let byte = bytes[index]
            if byte == 95 { continue }
            if byte == 88 || byte == 120 || byte == 90 || byte == 122 || byte == 63 {
                throw try failure("SV_SYNTHESIS_XZ_LITERAL", index..<(index + 1), source: source)
            }
            guard let digit = Self.digit(byte), digit < radix else {
                throw try failure("SV_LITERAL_INVALID_DIGIT", index..<(index + 1), source: source)
            }
            count += 1
        }
        return Header(width: width, signed: signed, radix: radix, digits: digits, digitCount: count)
    }

    @available(macOS 26.0, *)
    private func accumulate(_ header: Header, capacity: LogicBitWidth, bytes: borrowing Span<UInt8>,
                            context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogSynthesisLiteral {
        var words = [UInt64](repeating: 0, count: capacity.wordCount)
        for index in header.digits {
            try context.charge(.workUnits)
            if bytes[index] == 95 { continue }
            // Header admission has already validated every non-separator digit.
            var carry = Self.digit(bytes[index])!
            for word in words.indices {
                try context.charge(.workUnits)
                let product = words[word].multipliedFullWidth(by: header.radix)
                let sum = product.low.addingReportingOverflow(carry)
                words[word] = sum.partialValue
                carry = product.high + (sum.overflow ? 1 : 0)
            }
        }
        let width: LogicBitWidth
        if let declared = header.width { width = try LogicBitWidth(declared) }
        else {
            var significant = 0
            for index in words.indices.reversed() {
                try context.charge(.workUnits)
                if words[index] != 0 { significant = index * 64 + (64 - words[index].leadingZeroBitCount); break }
            }
            if header.radix == 10 && header.signed { significant += 1 }
            width = try LogicBitWidth(max(32, significant))
        }
        try context.observeBitWidth(UInt64(width.value))
        _ = try context.reserveStorage(byteCount: UInt64(width.wordCount) * 16)
        // Compact the temporary upper-bound limbs into the exact published plane count.
        var values = [UInt64](repeating: 0, count: width.wordCount)
        for index in values.indices { try context.charge(.workUnits); values[index] = words[index] }
        values[values.count - 1] &= width.tailMask
        let value = try LogicFourStateVector(width: width, valueWords: values,
            unknownWords: [UInt64](repeating: 0, count: width.wordCount))
        return .integer(value: value, isSigned: header.signed, isUnsized: header.width == nil)
    }

    @available(macOS 26.0, *)
    private func trim(_ range: Range<Int>, bytes: borrowing Span<UInt8>, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Range<Int> {
        var start = range.lowerBound; var end = range.upperBound
        while start < end && Self.isSpace(bytes[start]) { try context.charge(.workUnits); start += 1 }
        while start < end && Self.isSpace(bytes[end - 1]) { try context.charge(.workUnits); end -= 1 }
        return start..<end
    }
    private func failure(_ code: String, _ range: Range<Int>, source: borrowing SystemVerilogSourceText)
        throws(LogicKernelError) -> LogicKernelError {
        .sourceFailure(code: .trusted(code), source: try source.origin(for: range), message: "Invalid or unsupported synthesis integer literal")
    }
    private static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
    private static func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
    private static func digit(_ byte: UInt8) -> UInt64? {
        if isDigit(byte) { return UInt64(byte - 48) }
        if (65...70).contains(byte) { return UInt64(byte - 65 + 10) }
        if (97...102).contains(byte) { return UInt64(byte - 97 + 10) }
        return nil
    }
}
