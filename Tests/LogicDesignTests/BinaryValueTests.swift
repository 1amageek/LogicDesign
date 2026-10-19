import Testing
import LogicIR
import LogicKernelCore

@Suite(.timeLimit(.minutes(1)))
struct BinaryValueTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(control: any LogicRunControlling = Control(), storage: UInt64 = 10_000_000,
                         work: UInt64 = 10_000_000) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.workUnits] = work
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    private func value(_ integer: Int, width: Int) throws -> LogicFourStateVector {
        let width = try LogicBitWidth(width)
        return try LogicFourStateVector(width: width, valueWords: [UInt64(truncatingIfNeeded: integer) & width.tailMask], unknownWords: [0])
    }
    @available(macOS 26.0, *)
    private func integer(_ value: LogicFourStateVector, context: inout LogicKernelContext) throws -> Int {
        try value.binaryInt(signed: false, context: &context)
    }
    @Test func smallWidthsMatchIndependentArithmeticBitwiseAndComparison() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for width in 1...6 {
            var context = try context()
            let count = 1 << width; let mask = count - 1
            for left in 0..<count {
                let lhs = try value(left, width: width)
                for right in 0..<count {
                    let rhs = try value(right, width: width)
                    #expect(try integer(lhs.addingBinary(rhs, context: &context), context: &context) == (left + right) & mask)
                    #expect(try integer(lhs.subtractingBinary(rhs, context: &context), context: &context) == (left - right) & mask)
                    #expect(try integer(lhs.multiplyingBinary(rhs, context: &context), context: &context) == (left * right) & mask)
                    #expect(try integer(lhs.applyingBinary(.and, to: rhs, context: &context), context: &context) == left & right)
                    #expect(try integer(lhs.applyingBinary(.or, to: rhs, context: &context), context: &context) == left | right)
                    #expect(try integer(lhs.applyingBinary(.xor, to: rhs, context: &context), context: &context) == left ^ right)
                    #expect(try lhs.isLessThanBinary(rhs, signed: false, context: &context) == (left < right))
                    let signedLeft = left >= count / 2 ? left - count : left
                    let signedRight = right >= count / 2 ? right - count : right
                    #expect(try lhs.isLessThanBinary(rhs, signed: true, context: &context) == (signedLeft < signedRight))
                    #expect(try lhs.equalsBinary(rhs, context: &context) == (left == right))
                }
                #expect(try integer(lhs.negatingBinary(context: &context), context: &context) == (-left) & mask)
                #expect(try integer(lhs.invertingBinary(context: &context), context: &context) == (~left) & mask)
                #expect(try lhs.reducingBinary(.and, context: &context) == (left == mask))
                #expect(try lhs.reducingBinary(.or, context: &context) == (left != 0))
                #expect(try lhs.reducingBinary(.xor, context: &context) == (left.nonzeroBitCount % 2 != 0))
            }
        }
    }
    @Test func smallShiftsAndResizeMatchIndependentSignedAndUnsignedResults() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        for width in 1...7 {
            let count = 1 << width; let mask = count - 1
            for number in 0..<count {
                let operand = try value(number, width: width)
                let signed = number >= count / 2 ? number - count : number
                for shift in 0...(width + 3) {
                    let amount = try value(shift, width: 9)
                    #expect(try integer(operand.shiftingBinary(left: true, amount: amount, context: &context), context: &context) == (number << shift) & mask)
                    #expect(try integer(operand.shiftingBinary(left: false, amount: amount, context: &context), context: &context) == number >> shift)
                    #expect(try integer(operand.shiftingBinary(left: false, amount: amount, arithmetic: true, context: &context), context: &context) == (signed >> shift) & mask)
                }
                let extended = try LogicBitWidth(width + 5)
                #expect(try integer(operand.resizedBinary(to: extended, signExtend: false, context: &context), context: &context) == number)
                #expect(try integer(operand.resizedBinary(to: extended, signExtend: true, context: &context), context: &context) == signed & ((1 << extended.value) - 1))
                #expect(try operand.binaryInt(signed: true, context: &context) == signed)
                if width > 1 {
                    #expect(try integer(operand.resizedBinary(to: LogicBitWidth(width - 1), signExtend: true, context: &context), context: &context) == number & ((1 << (width - 1)) - 1))
                }
            }
        }
    }
    @Test func multiLimbCarryBorrowAndMultiplicationAreExactModuloWidth() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let width = try LogicBitWidth(129)
        let ones = try LogicFourStateVector(width: width, valueWords: [.max, .max, 1], unknownWords: [0, 0, 0])
        let zero = try LogicFourStateVector(repeating: .zero, width: width, context: &context)
        let one = try LogicFourStateVector(width: width, valueWords: [1, 0, 0], unknownWords: [0, 0, 0])
        #expect(try ones.addingBinary(one, context: &context) == zero)
        #expect(try zero.subtractingBinary(one, context: &context) == ones)
        #expect(try ones.multiplyingBinary(ones, context: &context) == one)
        #expect(try ones.negatingBinary(context: &context) == one)
        let limb = try LogicFourStateVector(width: width, valueWords: [.max, 0, 0], unknownWords: [0, 0, 0])
        let square = try limb.multiplyingBinary(limb, context: &context)
        #expect(square.withPlanes { $0[0] == 1 && $0[1] == .max - 1 && $0[2] == 0 && $1[2] == 0 })
        let padded = try value(-1, width: 5).resizedBinary(to: width, signExtend: true, context: &context)
        #expect(padded == ones)
        let narrow = try padded.resizedBinary(to: LogicBitWidth(65), signExtend: false, context: &context)
        #expect(narrow.withPlanes { words, _ in words.count == 2 && words[0] == .max && words[1] == 1 })
    }
    @Test func deterministicMultiLimbValuesMatchAnIndependentBitReference() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        var seed: UInt64 = 0x97531abcdf2468e1
        func randomWord() -> UInt64 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return seed
        }
        func referenceAdd(_ lhs: [Bool], _ rhs: [Bool], complement: Bool = false) -> [Bool] {
            var result = [Bool](repeating: false, count: lhs.count)
            var carry = complement ? 1 : 0
            for bit in lhs.indices {
                let right = complement ? !rhs[bit] : rhs[bit]
                let sum = (lhs[bit] ? 1 : 0) + (right ? 1 : 0) + carry
                result[bit] = sum % 2 != 0; carry = sum / 2
            }
            return result
        }
        func referenceMultiply(_ lhs: [Bool], _ rhs: [Bool]) -> [Bool] {
            var result = [Bool](repeating: false, count: lhs.count)
            for offset in lhs.indices where lhs[offset] {
                var carry = 0
                for bit in 0..<(lhs.count - offset) {
                    let sum = (result[bit + offset] ? 1 : 0) + (rhs[bit] ? 1 : 0) + carry
                    result[bit + offset] = sum % 2 != 0; carry = sum / 2
                }
            }
            return result
        }
        for bitCount in [65, 129, 193, 257] {
            let width = try LogicBitWidth(bitCount)
            for _ in 0..<16 {
                var left = (0..<width.wordCount).map { _ in randomWord() }
                var right = (0..<width.wordCount).map { _ in randomWord() }
                left[left.count - 1] &= width.tailMask; right[right.count - 1] &= width.tailMask
                let lhs = try LogicFourStateVector(width: width, valueWords: left, unknownWords: [UInt64](repeating: 0, count: width.wordCount))
                let rhs = try LogicFourStateVector(width: width, valueWords: right, unknownWords: [UInt64](repeating: 0, count: width.wordCount))
                let a = try (0..<bitCount).map { try lhs.bit(at: $0) == .one }
                let b = try (0..<bitCount).map { try rhs.bit(at: $0) == .one }
                let expected = [referenceAdd(a, b), referenceAdd(a, b, complement: true), referenceMultiply(a, b)]
                let actual = [try lhs.addingBinary(rhs, context: &context), try lhs.subtractingBinary(rhs, context: &context), try lhs.multiplyingBinary(rhs, context: &context)]
                for operation in actual.indices {
                    for bit in 0..<bitCount { #expect(try actual[operation].bit(at: bit) == (expected[operation][bit] ? .one : .zero)) }
                }
            }
        }
    }

    @Test func crossWordShiftsSlicesAndConcatenationPreserveEveryBit() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let width = try LogicBitWidth(129)
        let source = try LogicFourStateVector(width: width, valueWords: [0x123456789abcdef0, 0xfedcba9876543210, 1], unknownWords: [0, 0, 0])
        for shift in [0, 1, 31, 63, 64, 65, 127, 128, 129, 130] {
            let amount = try value(shift, width: 9)
            for left in [false, true] {
                for arithmetic in [false, true] {
                    let result = try source.shiftingBinary(left: left, amount: amount, arithmetic: arithmetic, context: &context)
                    for bit in 0..<129 {
                        let input = left ? bit - shift : bit + shift
                        let expected: LogicBit = input >= 0 && input < 129 ? try source.bit(at: input) : (!left && arithmetic ? .one : .zero)
                        #expect(try result.bit(at: bit) == expected)
                    }
                }
            }
        }
        let huge = try LogicFourStateVector(width: width, valueWords: [0, 0, 1], unknownWords: [0, 0, 0])
        #expect(try source.shiftingBinary(left: true, amount: huge, context: &context).reducingBinary(.or, context: &context) == false)
        #expect(try source.shiftingBinary(left: false, amount: huge, arithmetic: true, context: &context).reducingBinary(.and, context: &context))
        for offset in [0, 1, 63, 64, 65, 128] {
            let sliceWidth = try LogicBitWidth(129 - offset)
            let slice = try source.slicingBinary(offset: offset, width: sliceWidth, context: &context)
            for bit in 0..<sliceWidth.value { #expect(try slice.bit(at: bit) == source.bit(at: bit + offset)) }
        }
        for lowerWidth in [1, 31, 63, 64, 65, 128, 129] {
            let lower = try source.slicingBinary(offset: 0, width: LogicBitWidth(lowerWidth), context: &context)
            let joined = try source.concatenatingBinary(lower, context: &context)
            for bit in 0..<joined.width.value {
                #expect(try joined.bit(at: bit) == (bit < lowerWidth ? lower.bit(at: bit) : source.bit(at: bit - lowerWidth)))
            }
        }
    }
    @Test func checkedIndexConversionNeverLimitsTheCircuitValueDomain() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        for integer in [Int.min, -1, 0, 1, Int.max] {
            let native = try LogicFourStateVector(width: LogicBitWidth(Int.bitWidth), valueWords: [UInt64(truncatingIfNeeded: integer)], unknownWords: [0])
            let wide = try native.resizedBinary(to: LogicBitWidth(129), signExtend: true, context: &context)
            #expect(try wide.binaryInt(signed: true, context: &context) == integer)
            if integer < 0 { #expect(throws: LogicKernelError.self) { try wide.binaryInt(signed: false, context: &context) } }
        }
        let positiveOverflow = try LogicFourStateVector(width: LogicBitWidth(129), valueWords: [0, 1, 0], unknownWords: [0, 0, 0])
        #expect(throws: LogicKernelError.self) { try positiveOverflow.binaryInt(signed: true, context: &context) }
        let negativeOverflow = try positiveOverflow.negatingBinary(context: &context)
        #expect(throws: LogicKernelError.self) { try negativeOverflow.binaryInt(signed: true, context: &context) }
        #expect(try positiveOverflow.addingBinary(positiveOverflow, context: &context).withPlanes { words, _ in words[1] == 2 })
    }
    @Test func unknownWidthBoundsStorageAndCancellationCannotBecomeSuccess() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let one = try value(1, width: 1); let two = try value(2, width: 2)
        for bit in [LogicBit.unknown, .highImpedance] {
            let unknown = try LogicFourStateVector(repeating: bit, width: LogicBitWidth(1), context: &context)
            #expect(throws: LogicKernelError.self) { try unknown.addingBinary(one, context: &context) }
            #expect(throws: LogicKernelError.self) { try one.shiftingBinary(left: true, amount: unknown, context: &context) }
            #expect(throws: LogicKernelError.self) { try unknown.resizedBinary(to: LogicBitWidth(2), signExtend: true, context: &context) }
            #expect(throws: LogicKernelError.self) { try unknown.binaryInt(signed: false, context: &context) }
        }
        #expect(throws: LogicKernelError.self) { try one.addingBinary(two, context: &context) }
        #expect(throws: LogicKernelError.self) { try one.slicingBinary(offset: -1, width: LogicBitWidth(1), context: &context) }
        #expect(throws: LogicKernelError.self) { try one.slicingBinary(offset: 1, width: LogicBitWidth(1), context: &context) }
        var cancelled = try self.context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try one.resizedBinary(to: LogicBitWidth(1), signExtend: false, context: &cancelled) }
        #expect(throws: LogicKernelError.cancelled) { try one.shiftingBinary(left: true, amount: one, context: &cancelled) }
        var noStorage = try self.context(storage: 1)
        #expect(throws: LogicKernelError.self) { try one.addingBinary(one, context: &noStorage) }
        #expect(noStorage.usage[.allocationBytes] == 0)
        let before = context.usage[.allocationBytes]
        _ = try one.resizedBinary(to: LogicBitWidth(1), signExtend: true, context: &context)
        #expect(context.usage[.allocationBytes] == before)
        var tinyWidthLimits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100)) })
        tinyWidthLimits[.bitWidth] = 1
        var tinyWidth = LogicKernelContext(limits: try LogicKernelLimits(maximums: tinyWidthLimits), control: Control())
        #expect(throws: LogicKernelError.self) { try two.shiftingBinary(left: true, amount: value(0, width: 1), context: &tinyWidth) }
        #expect(tinyWidth.usage[.allocationBytes] == 0)
        let wide = try LogicFourStateVector(repeating: .one, width: LogicBitWidth(257), context: &context)
        var partialWork = try self.context(work: 12)
        #expect(throws: LogicKernelError.resourceLimit(resource: .workUnits, limit: 12, requested: 13)) {
            try wide.multiplyingBinary(wide, context: &partialWork)
        }
        #expect(partialWork.usage[.allocationBytes] == 80 && partialWork.usage[.workUnits] == 12)
        enum BorrowFailure: Error { case expected }
        #expect(throws: BorrowFailure.expected) {
            try one.withPlanes { (_, _) throws(BorrowFailure) in throw .expected }
        }
    }
}
