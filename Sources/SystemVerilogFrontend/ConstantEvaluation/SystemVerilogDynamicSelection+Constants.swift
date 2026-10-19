import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogDynamicSelection {
    // Normalize before narrowing: a wide source index may become a valid small
    // offset after subtracting a large declared bound.
    func constantOffset(_ input: LogicFourStateVector, signed: Bool,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Int? {
        let type = try offsetType(for: WordLogicType(width: input.width, isSigned: signed))
        try context.observeBitWidth(UInt64(type.width.value))
        var result = try input.resizedBinary(to: type.width, signExtend: signed, context: &context)
        if adjustment != 0 { result = try result.addingBinary(integer(adjustment, width: type.width, context: &context), context: &context) }
        let bound = try integer(rightBound, width: type.width, context: &context)
        result = try descending ? result.subtractingBinary(bound, context: &context) : bound.subtractingBinary(result, context: &context)
        if unit != 1 { result = try result.multiplyingBinary(integer(unit, width: type.width, context: &context), context: &context) }
        do throws(LogicKernelError) { return try result.binaryInt(signed: true, context: &context) }
        catch {
            if case .invalidModel = error { return nil }
            throw error
        }
    }
    private func integer(_ value: Int, width: LogicBitWidth, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicFourStateVector {
        _ = try context.reserveStorage(byteCount: UInt64(width.wordCount) * 16)
        var words = [UInt64](repeating: value < 0 ? .max : 0, count: width.wordCount)
        words[0] = UInt64(truncatingIfNeeded: value); words[words.count - 1] &= width.tailMask
        return try LogicFourStateVector(width: width, valueWords: words,
            unknownWords: [UInt64](repeating: 0, count: width.wordCount))
    }
}
