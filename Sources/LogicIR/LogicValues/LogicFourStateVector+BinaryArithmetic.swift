import LogicKernelCore

@available(macOS 26.0, *)
extension LogicFourStateVector {
    internal borrowing func requireBinary(context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.observeBitWidth(UInt64(width.value))
        try context.charge(.workUnits, amount: UInt64(width.wordCount))
        guard isTwoState else { throw .invalidModel("Binary value operation received X or Z") }
    }
    internal borrowing func requireBinaryPair(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        try requireBinary(context: &context); try other.requireBinary(context: &context)
        guard width == other.width else { throw .invalidModel("Binary value operand widths differ") }
    }
    internal static func makeBinary(width: LogicBitWidth, context: inout LogicKernelContext,
        _ body: (inout MutableSpan<UInt64>, inout LogicKernelContext) throws(LogicKernelError) -> Void)
        throws(LogicKernelError) -> Self {
        try context.observeBitWidth(UInt64(width.value))
        _ = try context.reserveStorage(byteCount: UInt64(width.wordCount) * 16)
        var words = [UInt64](repeating: 0, count: width.wordCount)
        do {
            var destination = words.mutableSpan
            try body(&destination, &context)
            destination[destination.count - 1] &= width.tailMask
        }
        return try Self(width: width, valueWords: words, unknownWords: [UInt64](repeating: 0, count: width.wordCount))
    }
    public borrowing func addingBinary(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try requireBinaryPair(other, context: &context)
        return try Self.makeBinary(width: width, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (lhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                try other.withPlanes { (rhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                    var carry: UInt64 = 0
                    for index in destination.indices {
                        try run.charge(.workUnits)
                        let sum = lhs[index].addingReportingOverflow(rhs[index])
                        let added = sum.partialValue.addingReportingOverflow(carry)
                        destination[index] = added.partialValue
                        carry = sum.overflow || added.overflow ? 1 : 0
                    }
                }
            }
        }
    }
    public borrowing func subtractingBinary(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try requireBinaryPair(other, context: &context)
        return try Self.makeBinary(width: width, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (lhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                try other.withPlanes { (rhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                    var borrow: UInt64 = 0
                    for index in destination.indices {
                        try run.charge(.workUnits)
                        let difference = lhs[index].subtractingReportingOverflow(rhs[index])
                        let subtracted = difference.partialValue.subtractingReportingOverflow(borrow)
                        destination[index] = subtracted.partialValue
                        borrow = difference.overflow || subtracted.overflow ? 1 : 0
                    }
                }
            }
        }
    }
    public borrowing func multiplyingBinary(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try requireBinaryPair(other, context: &context)
        return try Self.makeBinary(width: width, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (lhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                try other.withPlanes { (rhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                    for left in lhs.indices {
                        var carry: UInt64 = 0
                        for right in 0..<(destination.count - left) {
                            try run.charge(.workUnits)
                            let product = lhs[left].multipliedFullWidth(by: rhs[right])
                            let sum = product.low.addingReportingOverflow(destination[left + right])
                            let added = sum.partialValue.addingReportingOverflow(carry)
                            destination[left + right] = added.partialValue
                            // The full product plus two limbs is at most 2^128 - 1.
                            carry = product.high &+ (sum.overflow ? 1 : 0) &+ (added.overflow ? 1 : 0)
                        }
                    }
                }
            }
        }
    }
    public borrowing func negatingBinary(context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try requireBinary(context: &context)
        return try Self.makeBinary(width: width, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                var carry: UInt64 = 1
                for index in destination.indices {
                    try run.charge(.workUnits)
                    let sum = (~source[index]).addingReportingOverflow(carry)
                    destination[index] = sum.partialValue; carry = sum.overflow ? 1 : 0
                }
            }
        }
    }
    public borrowing func invertingBinary(context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try requireBinary(context: &context)
        return try Self.makeBinary(width: width, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (source: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                for index in destination.indices { try run.charge(.workUnits); destination[index] = ~source[index] }
            }
        }
    }
    public borrowing func applyingBinary(_ operation: LogicBinaryBitwiseOperation, to other: borrowing Self,
                                         context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try requireBinaryPair(other, context: &context)
        return try Self.makeBinary(width: width, context: &context) { destination, run throws(LogicKernelError) in
            try withPlanes { (lhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                try other.withPlanes { (rhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                    for index in destination.indices {
                        try run.charge(.workUnits)
                        switch operation {
                        case .and: destination[index] = lhs[index] & rhs[index]
                        case .or: destination[index] = lhs[index] | rhs[index]
                        case .xor: destination[index] = lhs[index] ^ rhs[index]
                        }
                    }
                }
            }
        }
    }
    public borrowing func reducingBinary(_ operation: LogicBinaryBitwiseOperation, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        try requireBinary(context: &context)
        return try withPlanes { (words: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
            var parity = false
            for index in words.indices {
                try context.charge(.workUnits)
                switch operation {
                case .and: if words[index] != (index == words.count - 1 ? width.tailMask : .max) { return false }
                case .or: if words[index] != 0 { return true }
                case .xor: parity = parity != (words[index].nonzeroBitCount % 2 != 0)
                }
            }
            return operation == .and || (operation == .xor && parity)
        }
    }
    public borrowing func isLessThanBinary(_ other: borrowing Self, signed: Bool, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        try requireBinaryPair(other, context: &context)
        return try withPlanes { (lhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
            try other.withPlanes { (rhs: borrowing Span<UInt64>, _: borrowing Span<UInt64>) throws(LogicKernelError) in
                if signed {
                    let sign = UInt64(1) << ((width.value - 1) % 64)
                    let negative = lhs[lhs.count - 1] & sign != 0
                    let otherNegative = rhs[rhs.count - 1] & sign != 0
                    if negative != otherNegative { return negative }
                }
                for index in lhs.indices.reversed() {
                    try context.charge(.workUnits)
                    if lhs[index] != rhs[index] { return lhs[index] < rhs[index] }
                }
                return false
            }
        }
    }
    public borrowing func equalsBinary(_ other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        try requireBinaryPair(other, context: &context)
        try context.charge(.workUnits, amount: UInt64(width.wordCount))
        return self == other
    }
}
