import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public nonisolated func exerciseFourStateValueContract() throws(LogicKernelError) {
    var context = LogicKernelContext(
        limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, UInt64(10_000_000)) })), control: FourStateProbeControl())
    let andTable: [UInt8] = [0,0,0,0, 0,1,2,2, 0,2,2,2, 0,2,2,2]
    let orTable: [UInt8] = [0,1,2,2, 1,1,1,1, 2,1,2,2, 2,1,2,2]
    let xorTable: [UInt8] = [0,1,2,2, 1,0,2,2, 2,2,2,2, 2,2,2,2]
    let width = try LogicBitWidth(1)
    for a in UInt8(0)...3 {
        let lhs = try LogicFourStateVector(width: width, valueWords: [UInt64(a & 1)], unknownWords: [UInt64(a >> 1)])
        for b in UInt8(0)...3 {
            let rhs = try LogicFourStateVector(width: width, valueWords: [UInt64(b & 1)], unknownWords: [UInt64(b >> 1)])
            for operation in [LogicBinaryBitwiseOperation.and, .or, .xor] {
                let table = operation == .and ? andTable : operation == .or ? orTable : xorTable
                let result = try lhs.applyingFourState(operation, to: rhs, context: &context)
                guard try result.bit(at: 0).rawValue == table[Int(a) * 4 + Int(b)] else {
                    throw .invalidModel("Four-state packed truth table mismatch")
                }
            }
            for c in UInt8(0)...3 {
                let predicate = try LogicFourStateVector(width: width, valueWords: [UInt64(c & 1)], unknownWords: [UInt64(c >> 1)])
                let result = try predicate.selectingFourState(ifTrue: lhs, ifFalse: rhs, context: &context)
                let expected = c == 0 ? b : c == 1 ? a : a < 2 && a == b ? a : 2
                guard try result.bit(at: 0).rawValue == expected,
                      LogicBit(rawValue: c)!.selecting(ifTrue: LogicBit(rawValue: a)!, ifFalse: LogicBit(rawValue: b)!).rawValue == expected else {
                    throw .invalidModel("Four-state conditional table mismatch")
                }
            }
        }
    }
    let wide = try LogicFourStateVector(width: LogicBitWidth(129), valueWords: [.max, 0x123456789abcdef0, 1],
                                      unknownWords: [.max, 0xfedcba9876543210, 1])
    let extended = try wide.resizedFourState(to: LogicBitWidth(257), signExtend: true, context: &context)
    let huge = try LogicFourStateVector(width: LogicBitWidth(129), valueWords: [0, 0, 1], unknownWords: [0, 0, 0])
    let shifted = try wide.shiftingFourState(left: false, amount: huge, arithmetic: true, context: &context)
    for index in 129..<257 {
        guard try extended.bit(at: index) == .highImpedance else { throw .invalidModel("Four-state sign extension lost Z") }
    }
    for index in 0..<129 {
        guard try shifted.bit(at: index) == .highImpedance else { throw .invalidModel("Four-state overshift lost Z") }
    }
    let ambiguous = try LogicFourStateVector(width: width, valueWords: [1], unknownWords: [1])
    let unknownShift = try wide.shiftingFourState(left: true, amount: ambiguous, context: &context)
    guard try unknownShift.reducingFourState(.xor, context: &context) == .unknown else {
        throw .invalidModel("Four-state unknown shift lost X")
    }
    var cancelled = LogicKernelContext(limits: context.limits, control: FourStateProbeCancelled())
    do throws(LogicKernelError) {
        _ = try wide.resizedFourState(to: wide.width, signExtend: false, context: &cancelled)
        throw .invalidModel("Four-state identity ignored cancellation")
    } catch .cancelled {} catch { throw error }
}

private struct FourStateProbeControl: LogicRunControlling {
    func checkpoint() throws(LogicKernelError) {}
}

private struct FourStateProbeCancelled: LogicRunControlling {
    func checkpoint() throws(LogicKernelError) { throw .cancelled }
}
