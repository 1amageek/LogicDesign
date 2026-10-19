import LogicKernelCore

@available(macOS 26.0, *)
extension LogicFourStateVector {
    public borrowing func resizedFourState(to resultWidth: LogicBitWidth, signExtend: Bool,
                                          context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try admitFourState(context: &context)
        try context.observeBitWidth(UInt64(resultWidth.value))
        if width == resultWidth { return copy self }
        return try Self.makeFourState(width: resultWidth, context: &context) { values, unknowns, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, mask: borrowing Span<UInt64>) throws(LogicKernelError) in
                for index in values.indices {
                    try run.charge(.workUnits)
                    values[index] = Self.extendedPlaneWord(source, at: index, width: width, extend: signExtend)
                    unknowns[index] = Self.extendedPlaneWord(mask, at: index, width: width, extend: signExtend)
                }
            }
        }
    }

    public borrowing func shiftingFourState(left: Bool, amount: borrowing Self, arithmetic: Bool = false,
                                           context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try admitFourState(context: &context)
        if try amount.containsUnknown(context: &context) {
            return try Self.unknownFourState(width: width, context: &context)
        }
        let distance: Int? = try amount.withPlanes { (words: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
            for index in words.indices {
                try context.charge(.workUnits)
                if index > 0 && words[index] != 0 { return nil }
            }
            return words[0] < UInt64(width.value) ? Int(words[0]) : nil
        }
        if distance == 0 { return copy self }
        return try Self.makeFourState(width: width, context: &context) { values, unknowns, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, mask: borrowing Span<UInt64>) throws(LogicKernelError) in
                for index in values.indices {
                    try run.charge(.workUnits)
                    values[index] = Self.shiftedPlaneWord(source, at: index, width: width,
                                                         left: left, distance: distance, arithmetic: arithmetic)
                    unknowns[index] = Self.shiftedPlaneWord(mask, at: index, width: width,
                                                           left: left, distance: distance, arithmetic: arithmetic)
                }
            }
        }
    }

    public borrowing func slicingFourState(offset: Int, width resultWidth: LogicBitWidth,
                                          context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try admitFourState(context: &context)
        try context.observeBitWidth(UInt64(resultWidth.value))
        guard offset >= 0, resultWidth.value <= width.value, offset <= width.value - resultWidth.value else {
            throw .invalidModel("Four-state slice is outside the value")
        }
        if offset == 0 && resultWidth == width { return copy self }
        return try Self.makeFourState(width: resultWidth, context: &context) { values, unknowns, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, mask: borrowing Span<UInt64>) throws(LogicKernelError) in
                for index in values.indices {
                    try run.charge(.workUnits)
                    values[index] = Self.shiftedPlaneWord(source, at: index, width: width,
                                                         left: false, distance: offset, arithmetic: false)
                    unknowns[index] = Self.shiftedPlaneWord(mask, at: index, width: width,
                                                           left: false, distance: offset, arithmetic: false)
                }
            }
        }
    }

    public borrowing func concatenatingFourState(_ lower: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try admitFourState(context: &context)
        try lower.admitFourState(context: &context)
        let sum = width.value.addingReportingOverflow(lower.width.value)
        guard !sum.overflow else { throw .invalidModel("Four-state concatenation width overflow") }
        let combined = try LogicBitWidth(sum.partialValue)
        return try Self.makeFourState(width: combined, context: &context) { values, unknowns, run throws(LogicKernelError) in
            try lower.withPlanes { (source: borrowing Span<UInt64>, mask: borrowing Span<UInt64>) throws(LogicKernelError) in
                for index in source.indices {
                    try run.charge(.workUnits)
                    values[index] = source[index]
                    unknowns[index] = mask[index]
                }
            }
            try withPlanes { (source: borrowing Span<UInt64>, mask: borrowing Span<UInt64>) throws(LogicKernelError) in
                let wordOffset = lower.width.value / 64
                let bitOffset = lower.width.value % 64
                for index in source.indices {
                    try run.charge(.workUnits)
                    let output = index + wordOffset
                    values[output] |= source[index] << bitOffset
                    unknowns[output] |= mask[index] << bitOffset
                    if bitOffset != 0 && output + 1 < values.count {
                        values[output + 1] |= source[index] >> (64 - bitOffset)
                        unknowns[output + 1] |= mask[index] >> (64 - bitOffset)
                    }
                }
            }
        }
    }

    private static func extendedPlaneWord(_ words: borrowing Span<UInt64>, at index: Int,
                                          width: LogicBitWidth, extend: Bool) -> UInt64 {
        let sign = extend && words[words.count - 1] & (UInt64(1) << ((width.value - 1) % 64)) != 0
        guard index < words.count else { return sign ? .max : 0 }
        return sign && index == words.count - 1 ? words[index] | ~width.tailMask : words[index]
    }

    private static func shiftedPlaneWord(_ words: borrowing Span<UInt64>, at index: Int,
                                         width: LogicBitWidth, left: Bool, distance: Int?, arithmetic: Bool) -> UInt64 {
        guard let distance else {
            return extendedPlaneWord(words, at: words.count, width: width, extend: !left && arithmetic)
        }
        let wordOffset = distance / 64
        let bitOffset = distance % 64
        if left {
            guard index >= wordOffset else { return 0 }
            let input = index - wordOffset
            var result = words[input] << bitOffset
            if bitOffset != 0 && input > 0 { result |= words[input - 1] >> (64 - bitOffset) }
            return result
        }
        let input = index + wordOffset
        var result = extendedPlaneWord(words, at: input, width: width, extend: arithmetic) >> bitOffset
        if bitOffset != 0 {
            result |= extendedPlaneWord(words, at: input + 1, width: width, extend: arithmetic) << (64 - bitOffset)
        }
        return result
    }
}
