import LogicKernelCore

@available(macOS 26.0, *)
extension LogicFourStateVector {
    internal borrowing func admitFourState(context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.observeBitWidth(UInt64(width.value))
    }

    internal borrowing func admitFourStatePair(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        try admitFourState(context: &context)
        try other.admitFourState(context: &context)
        guard width == other.width else { throw .invalidModel("Four-state operand widths differ") }
    }

    internal static func makeFourState(
        width: LogicBitWidth, context: inout LogicKernelContext,
        _ body: (inout MutableSpan<UInt64>, inout MutableSpan<UInt64>, inout LogicKernelContext)
            throws(LogicKernelError) -> Void
    ) throws(LogicKernelError) -> Self {
        try context.observeBitWidth(UInt64(width.value))
        _ = try context.reserveStorage(byteCount: UInt64(width.wordCount) * 16)
        var values = [UInt64](repeating: 0, count: width.wordCount)
        var unknowns = [UInt64](repeating: 0, count: width.wordCount)
        do {
            var valueView = values.mutableSpan
            var unknownView = unknowns.mutableSpan
            try body(&valueView, &unknownView, &context)
            valueView[valueView.count - 1] &= width.tailMask
            unknownView[unknownView.count - 1] &= width.tailMask
        }
        return try Self(width: width, valueWords: values, unknownWords: unknowns)
    }

    internal borrowing func containsUnknown(context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        try admitFourState(context: &context)
        return try withPlanes { (_: borrowing Span<UInt64>, unknowns: borrowing Span<UInt64>) throws(LogicKernelError) in
            for index in unknowns.indices {
                try context.charge(.workUnits)
                if unknowns[index] != 0 { return true }
            }
            return false
        }
    }

    internal static func unknownFourState(width: LogicBitWidth, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try makeFourState(width: width, context: &context) { _, unknowns, run throws(LogicKernelError) in
            for index in unknowns.indices { try run.charge(.workUnits); unknowns[index] = .max }
        }
    }

    public borrowing func invertingFourState(context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try admitFourState(context: &context)
        return try Self.makeFourState(width: width, context: &context) { values, unknowns, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, mask: borrowing Span<UInt64>) throws(LogicKernelError) in
                for index in values.indices {
                    try run.charge(.workUnits)
                    values[index] = ~source[index] & ~mask[index]
                    unknowns[index] = mask[index]
                }
            }
        }
    }

    public borrowing func applyingFourState(
        _ operation: LogicBinaryBitwiseOperation, to other: borrowing Self, context: inout LogicKernelContext
    ) throws(LogicKernelError) -> Self {
        try admitFourStatePair(other, context: &context)
        return try Self.makeFourState(width: width, context: &context) { values, unknowns, run throws(LogicKernelError) in
            try withPlanes { (a: borrowing Span<UInt64>, ax: borrowing Span<UInt64>) throws(LogicKernelError) in
                try other.withPlanes { (b: borrowing Span<UInt64>, bx: borrowing Span<UInt64>) throws(LogicKernelError) in
                    for index in values.indices {
                        try run.charge(.workUnits)
                        switch operation {
                        case .and:
                            let knownZero = (~a[index] & ~ax[index]) | (~b[index] & ~bx[index])
                            let knownOne = a[index] & ~ax[index] & b[index] & ~bx[index]
                            values[index] = knownOne
                            unknowns[index] = ~(knownZero | knownOne)
                        case .or:
                            let knownOne = (a[index] & ~ax[index]) | (b[index] & ~bx[index])
                            let knownZero = ~a[index] & ~ax[index] & ~b[index] & ~bx[index]
                            values[index] = knownOne
                            unknowns[index] = ~(knownZero | knownOne)
                        case .xor:
                            unknowns[index] = ax[index] | bx[index]
                            values[index] = (a[index] ^ b[index]) & ~unknowns[index]
                        }
                    }
                }
            }
        }
    }

    public borrowing func reducingFourState(_ operation: LogicBinaryBitwiseOperation,
                                           context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBit {
        try admitFourState(context: &context)
        return try withPlanes { (values: borrowing Span<UInt64>, unknowns: borrowing Span<UInt64>) throws(LogicKernelError) in
            var ambiguous = false
            var parity = false
            for index in values.indices {
                try context.charge(.workUnits)
                let valid: UInt64 = index == values.count - 1 ? width.tailMask : .max
                switch operation {
                case .and: if (~values[index] & ~unknowns[index] & valid) != 0 { return .zero }
                case .or: if (values[index] & ~unknowns[index]) != 0 { return .one }
                case .xor: parity = parity != (values[index].nonzeroBitCount % 2 != 0)
                }
                ambiguous = ambiguous || unknowns[index] != 0
            }
            if ambiguous { return .unknown }
            return operation == .and || (operation == .xor && parity) ? .one : .zero
        }
    }

    public borrowing func logicalFourState(context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBit {
        try reducingFourState(.or, context: &context)
    }

    public borrowing func equalsFourState(_ other: borrowing Self, caseEquality: Bool = false,
                                         context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBit {
        try admitFourStatePair(other, context: &context)
        return try withPlanes { (a: borrowing Span<UInt64>, ax: borrowing Span<UInt64>) throws(LogicKernelError) in
            try other.withPlanes { (b: borrowing Span<UInt64>, bx: borrowing Span<UInt64>) throws(LogicKernelError) in
                var ambiguous = false
                for index in a.indices {
                    try context.charge(.workUnits)
                    if caseEquality {
                        if a[index] != b[index] || ax[index] != bx[index] { return .zero }
                    } else {
                        if (a[index] ^ b[index]) & ~(ax[index] | bx[index]) != 0 { return .zero }
                        ambiguous = ambiguous || ax[index] | bx[index] != 0
                    }
                }
                return ambiguous ? .unknown : .one
            }
        }
    }

    public borrowing func isLessThanFourState(_ other: borrowing Self, signed: Bool,
                                             context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBit {
        try admitFourStatePair(other, context: &context)
        if try containsUnknown(context: &context) { return .unknown }
        if try other.containsUnknown(context: &context) { return .unknown }
        return try isLessThanBinary(other, signed: signed, context: &context) ? .one : .zero
    }

    public borrowing func selectingFourState(ifTrue: borrowing Self, ifFalse: borrowing Self,
                                             context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try ifTrue.admitFourStatePair(ifFalse, context: &context)
        let predicate = try logicalFourState(context: &context)
        switch predicate {
        case .one: return copy ifTrue
        case .zero: return copy ifFalse
        case .unknown, .highImpedance: break
        }
        return try Self.makeFourState(width: ifTrue.width, context: &context) { values, unknowns, run throws(LogicKernelError) in
            try ifTrue.withPlanes { (a: borrowing Span<UInt64>, ax: borrowing Span<UInt64>) throws(LogicKernelError) in
                try ifFalse.withPlanes { (b: borrowing Span<UInt64>, bx: borrowing Span<UInt64>) throws(LogicKernelError) in
                    for index in values.indices {
                        try run.charge(.workUnits)
                        let same = ~(a[index] ^ b[index]) & ~(ax[index] | bx[index])
                        values[index] = a[index] & same
                        unknowns[index] = ~same
                    }
                }
            }
        }
    }

    public borrowing func addingFourState(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try admitFourStatePair(other, context: &context)
        if try containsUnknown(context: &context) { return try Self.unknownFourState(width: width, context: &context) }
        if try other.containsUnknown(context: &context) { return try Self.unknownFourState(width: width, context: &context) }
        return try addingBinary(other, context: &context)
    }

    public borrowing func subtractingFourState(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try admitFourStatePair(other, context: &context)
        if try containsUnknown(context: &context) { return try Self.unknownFourState(width: width, context: &context) }
        if try other.containsUnknown(context: &context) { return try Self.unknownFourState(width: width, context: &context) }
        return try subtractingBinary(other, context: &context)
    }

    public borrowing func multiplyingFourState(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try admitFourStatePair(other, context: &context)
        if try containsUnknown(context: &context) { return try Self.unknownFourState(width: width, context: &context) }
        if try other.containsUnknown(context: &context) { return try Self.unknownFourState(width: width, context: &context) }
        return try multiplyingBinary(other, context: &context)
    }

    public borrowing func negatingFourState(context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        if try containsUnknown(context: &context) { return try Self.unknownFourState(width: width, context: &context) }
        return try negatingBinary(context: &context)
    }
}
