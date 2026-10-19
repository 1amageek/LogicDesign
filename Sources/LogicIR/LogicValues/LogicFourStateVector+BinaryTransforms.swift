import LogicKernelCore

@available(macOS 26.0, *)
extension LogicFourStateVector {
    public borrowing func resizedBinary(to resultWidth: LogicBitWidth, signExtend: Bool,
                                         context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try requireBinary(context: &context)
        try context.observeBitWidth(UInt64(resultWidth.value))
        if width == resultWidth { return copy self }
        return try Self.makeBinary(width: resultWidth, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                let negative = signExtend && (source[source.count - 1] >> ((width.value - 1) % 64)) & 1 != 0
                for index in destination.indices {
                    try run.charge(.workUnits)
                    destination[index] = Self.paddedWord(source, at: index, width: width, negative: negative)
                }
            }
        }
    }
    public borrowing func shiftingBinary(left: Bool, amount: borrowing Self, arithmetic: Bool = false,
                                          context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try requireBinary(context: &context); try amount.requireBinary(context: &context)
        let distance: Int? = try amount.withPlanes { (words: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
            for index in 1..<words.count { try context.charge(.workUnits); if words[index] != 0 { return nil } }
            return words[0] < UInt64(width.value) ? Int(words[0]) : nil
        }
        if distance == 0 { return copy self }
        return try Self.makeBinary(width: width, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                let negative = !left && arithmetic && (source[source.count - 1] >> ((width.value - 1) % 64)) & 1 != 0
                guard let distance else {
                    for index in destination.indices { try run.charge(.workUnits); destination[index] = negative ? .max : 0 }
                    return
                }
                let wordOffset = distance / 64; let bitOffset = distance % 64
                for index in destination.indices {
                    try run.charge(.workUnits)
                    if left {
                        guard index >= wordOffset else { continue }
                        let input = index - wordOffset
                        destination[index] = source[input] << bitOffset
                        if bitOffset != 0 && input > 0 { destination[index] |= source[input - 1] >> (64 - bitOffset) }
                    } else {
                        let input = index + wordOffset
                        destination[index] = Self.paddedWord(source, at: input, width: width, negative: negative) >> bitOffset
                        if bitOffset != 0 {
                            destination[index] |= Self.paddedWord(source, at: input + 1, width: width, negative: negative) << (64 - bitOffset)
                        }
                    }
                }
            }
        }
    }
    public borrowing func concatenatingBinary(_ lower: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try requireBinary(context: &context); try lower.requireBinary(context: &context)
        let sum = width.value.addingReportingOverflow(lower.width.value)
        guard !sum.overflow else { throw .invalidModel("Binary concatenation width overflow") }
        let combined = try LogicBitWidth(sum.partialValue)
        return try Self.makeBinary(width: combined, context: &context) { destination, run throws(LogicKernelError) in
            try lower.withPlanes { (source: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                for index in source.indices { try run.charge(.workUnits); destination[index] = source[index] }
            }
            try withPlanes { (source: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                let wordOffset = lower.width.value / 64; let bitOffset = lower.width.value % 64
                for index in source.indices {
                    try run.charge(.workUnits)
                    let output = index + wordOffset
                    destination[output] |= source[index] << bitOffset
                    if bitOffset != 0 && output + 1 < destination.count {
                        destination[output + 1] |= source[index] >> (64 - bitOffset)
                    }
                }
            }
        }
    }
    public borrowing func slicingBinary(offset: Int, width resultWidth: LogicBitWidth,
                                         context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try requireBinary(context: &context)
        guard offset >= 0, resultWidth.value <= width.value, offset <= width.value - resultWidth.value else {
            throw .invalidModel("Binary slice is outside the value")
        }
        return try Self.makeBinary(width: resultWidth, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                let wordOffset = offset / 64; let bitOffset = offset % 64
                for index in destination.indices {
                    try run.charge(.workUnits)
                    let input = index + wordOffset
                    destination[index] = source[input] >> bitOffset
                    if bitOffset != 0 && input + 1 < source.count { destination[index] |= source[input + 1] << (64 - bitOffset) }
                }
            }
        }
    }
    public borrowing func binaryInt(signed: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        try requireBinary(context: &context)
        return try withPlanes { (source: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
            let negative = signed && (source[source.count - 1] >> ((width.value - 1) % 64)) & 1 != 0
            let boundary = Int.bitWidth - 1
            if width.value > boundary {
                for index in (boundary / 64)..<source.count {
                    try context.charge(.workUnits)
                    var mask = UInt64.max << (index == boundary / 64 ? boundary % 64 : 0)
                    if index == source.count - 1 { mask &= width.tailMask }
                    guard source[index] & mask == (negative ? mask : 0) else {
                        throw .invalidModel("Binary value cannot be represented as a target table index")
                    }
                }
            }
            let low = source[0] | (negative && width.value < 64 ? ~width.tailMask : 0)
            return Int(truncatingIfNeeded: low)
        }
    }
    private static func paddedWord(_ source: borrowing Span<UInt64>, at index: Int,
                                   width: LogicBitWidth, negative: Bool) -> UInt64 {
        guard index < source.count else { return negative ? .max : 0 }
        let word = source[index]
        return negative && index == source.count - 1 ? word | ~width.tailMask : word
    }
}
