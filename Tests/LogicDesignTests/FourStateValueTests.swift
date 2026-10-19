import Testing
import LogicIR
import LogicKernelCore
import LogicKernelProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct FourStateValueTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(storage: UInt64 = 100_000_000, work: UInt64 = 100_000_000,
                         width: UInt64 = 100_000, control: any LogicRunControlling = Control()) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.workUnits] = work; limits[.bitWidth] = width
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    private func value(_ bits: [UInt8]) throws -> LogicFourStateVector {
        let width = try LogicBitWidth(bits.count)
        var values = [UInt64](repeating: 0, count: width.wordCount)
        var unknowns = values
        for index in bits.indices {
            values[index / 64] |= UInt64(bits[index] & 1) << (index % 64)
            unknowns[index / 64] |= UInt64(bits[index] >> 1) << (index % 64)
        }
        return try LogicFourStateVector(width: width, valueWords: values, unknownWords: unknowns)
    }
    private func bits(_ value: LogicFourStateVector) throws -> [UInt8] {
        try (0..<value.width.value).map { try value.bit(at: $0).rawValue }
    }
    @Test func scalarTablesAndPortableWideCases() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        try exerciseFourStateValueContract()
    }
    @Test func exhaustiveVectorsDistinguishControllingBitsEqualityAndReduction() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let tables: [[UInt8]] = [
            [0,0,0,0, 0,1,2,2, 0,2,2,2, 0,2,2,2],
            [0,1,2,2, 1,1,1,1, 2,1,2,2, 2,1,2,2],
            [0,1,2,2, 1,0,2,2, 2,2,2,2, 2,2,2,2]
        ]
        let operations: [LogicBinaryBitwiseOperation] = [.and, .or, .xor]
        for a in 0..<64 {
            let ab = (0..<3).map { UInt8((a >> ($0 * 2)) & 3) }
            let lhs = try value(ab)
            #expect(try bits(lhs.invertingFourState(context: &run)) == ab.map { $0 == 0 ? 1 : $0 == 1 ? 0 : 2 })
            for index in operations.indices {
                let expected = ab.reduce(index == 0 ? UInt8(1) : UInt8(0)) { tables[index][Int($0) * 4 + Int($1)] }
                #expect(try lhs.reducingFourState(operations[index], context: &run).rawValue == expected)
            }
            let truth: UInt8 = ab.contains(1) ? 1 : ab.contains(where: { $0 > 1 }) ? 2 : 0
            #expect(try lhs.logicalFourState(context: &run).rawValue == truth)
            for b in 0..<64 {
                let bb = (0..<3).map { UInt8((b >> ($0 * 2)) & 3) }
                let rhs = try value(bb)
                for index in operations.indices {
                    let expected = ab.indices.map { tables[index][Int(ab[$0]) * 4 + Int(bb[$0])] }
                    #expect(try bits(lhs.applyingFourState(operations[index], to: rhs, context: &run)) == expected)
                }
                let mismatch = ab.indices.contains { ab[$0] < 2 && bb[$0] < 2 && ab[$0] != bb[$0] }
                let ambiguous = ab.contains(where: { $0 > 1 }) || bb.contains(where: { $0 > 1 })
                #expect(try lhs.equalsFourState(rhs, context: &run).rawValue == (mismatch ? 0 : ambiguous ? 2 : 1))
                #expect(try lhs.equalsFourState(rhs, caseEquality: true, context: &run).rawValue == (ab == bb ? 1 : 0))
                for c in 0..<4 {
                    let predicate = try value([UInt8(c)])
                    let expected = ab.indices.map { c == 0 ? bb[$0] : c == 1 ? ab[$0] : ab[$0] < 2 && ab[$0] == bb[$0] ? ab[$0] : 2 }
                    #expect(try bits(predicate.selectingFourState(ifTrue: lhs, ifFalse: rhs, context: &run)) == expected)
                }
            }
        }
    }
    @Test func structuralTransformsPreserveEveryPlaneAcrossWordBoundaries() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        for width in [1, 63, 64, 65, 129, 257] {
            for sign in UInt8(0)...3 {
                var source = (0..<width).map { UInt8(($0 * 7 + $0 / 3) % 4) }
                source[width - 1] = sign
                let operand = try value(source)
                for resultWidth in [1, width, width + 1, width + 65] {
                    for extend in [false, true] {
                        let resized = try operand.resizedFourState(to: LogicBitWidth(resultWidth), signExtend: extend, context: &run)
                        let expected = (0..<resultWidth).map { $0 < width ? source[$0] : extend ? sign : 0 }
                        #expect(try bits(resized) == expected)
                    }
                }
                for offset in [0, width / 2, width - 1] {
                    let slice = try operand.slicingFourState(offset: offset, width: LogicBitWidth(width - offset), context: &run)
                    #expect(try bits(slice) == Array(source[offset...]))
                }
                for lowerWidth in [1, 63, 64, 65, 129] {
                    let lower = (0..<lowerWidth).map { UInt8($0 % 4) }
                    #expect(try bits(operand.concatenatingFourState(value(lower), context: &run)) == lower + source)
                }
                for distance in [0, 1, 63, 64, 65, width - 1, width, width + 1] {
                    let amount = try LogicFourStateVector(width: LogicBitWidth(129), valueWords: [UInt64(distance), 0, 0], unknownWords: [0, 0, 0])
                    for left in [false, true] {
                        for arithmetic in [false, true] {
                            let shifted = try operand.shiftingFourState(left: left, amount: amount, arithmetic: arithmetic, context: &run)
                            let expected = (0..<width).map { bit -> UInt8 in
                                let input = left ? bit - distance : bit + distance
                                return input >= 0 && input < width ? source[input] : !left && arithmetic ? sign : 0
                            }
                            #expect(try bits(shifted) == expected)
                        }
                    }
                }
            }
        }
    }
    @Test func arithmeticAndRelationalOperatorsPropagateAllUnknownBits() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        for a in 0..<64 {
            let ab = (0..<3).map { UInt8((a >> ($0 * 2)) & 3) }
            let lhs = try value(ab)
            let ai = ab.indices.reduce(0) { $0 | (Int(ab[$1] & 1) << $1) }
            let unknown = ab.contains(where: { $0 > 1 })
            let negated = try lhs.negatingFourState(context: &run)
            #expect(try bits(negated) == (unknown ? [2,2,2] : (0..<3).map { UInt8(((-ai) >> $0) & 1) }))
            for b in 0..<64 {
                let bb = (0..<3).map { UInt8((b >> ($0 * 2)) & 3) }
                let rhs = try value(bb)
                let bi = bb.indices.reduce(0) { $0 | (Int(bb[$1] & 1) << $1) }
                let ambiguous = unknown || bb.contains(where: { $0 > 1 })
                let actual = [try lhs.addingFourState(rhs, context: &run), try lhs.subtractingFourState(rhs, context: &run), try lhs.multiplyingFourState(rhs, context: &run)]
                let integers = [ai + bi, ai - bi, ai * bi]
                for index in actual.indices {
                    let expected = ambiguous ? [UInt8](repeating: 2, count: 3) : (0..<3).map { UInt8((integers[index] >> $0) & 1) }
                    #expect(try bits(actual[index]) == expected)
                }
                for signed in [false, true] {
                    let av = signed && ai >= 4 ? ai - 8 : ai
                    let bv = signed && bi >= 4 ? bi - 8 : bi
                    #expect(try lhs.isLessThanFourState(rhs, signed: signed, context: &run).rawValue == (ambiguous ? 2 : av < bv ? 1 : 0))
                }
            }
        }
    }
    @Test func unknownDistancesHugeDistancesAndControllingBitsRemainDistinct() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let wide = try value([UInt8](repeating: 3, count: 129))
        let huge = try LogicFourStateVector(width: LogicBitWidth(129), valueWords: [0, 1, 0], unknownWords: [0, 0, 0])
        #expect(try bits(wide.shiftingFourState(left: true, amount: huge, arithmetic: true, context: &run)) == [UInt8](repeating: 0, count: 129))
        #expect(try bits(wide.shiftingFourState(left: false, amount: huge, arithmetic: true, context: &run)) == [UInt8](repeating: 3, count: 129))
        for bit in UInt8(2)...3 {
            let amount = try value([bit])
            #expect(try bits(wide.shiftingFourState(left: false, amount: amount, arithmetic: true, context: &run)) == [UInt8](repeating: 2, count: 129))
        }
        var mixed = [UInt8](repeating: 2, count: 129)
        mixed[128] = 1
        #expect(try value(mixed).logicalFourState(context: &run) == .one)
        mixed[128] = 0
        #expect(try value(mixed).reducingFourState(.and, context: &run) == .zero)
        #expect(try value([2,0]).equalsFourState(value([2,1]), context: &run) == .zero)
        #expect(try value([2,0]).equalsFourState(value([2,0]), context: &run) == .unknown)
    }
    @Test func failedAdmissionAndIdentityOperationsNeverHideFailure() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let one = try value([1]); let wide = try value([UInt8](repeating: 3, count: 129))
        var run = try context()
        #expect(throws: LogicKernelError.self) { try one.applyingFourState(.and, to: wide, context: &run) }
        #expect(throws: LogicKernelError.self) { try one.addingFourState(wide, context: &run) }
        #expect(throws: LogicKernelError.self) { try one.equalsFourState(wide, context: &run) }
        #expect(throws: LogicKernelError.self) { try one.selectingFourState(ifTrue: one, ifFalse: wide, context: &run) }
        #expect(throws: LogicKernelError.self) { try wide.slicingFourState(offset: Int.max, width: one.width, context: &run) }
        var noStorage = try context(storage: 1)
        #expect(throws: LogicKernelError.self) { try wide.invertingFourState(context: &noStorage) }
        #expect(noStorage.usage[.allocationBytes] == 0)
        var noWork = try context(work: 1)
        #expect(throws: LogicKernelError.self) { try wide.invertingFourState(context: &noWork) }
        #expect(noWork.usage[.workUnits] == 1)
        var narrow = try context(width: 1)
        #expect(throws: LogicKernelError.self) { try one.selectingFourState(ifTrue: wide, ifFalse: wide, context: &narrow) }
        #expect(narrow.usage[.allocationBytes] == 0)
        var cancelled = try context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try wide.resizedFourState(to: wide.width, signExtend: false, context: &cancelled) }
        #expect(throws: LogicKernelError.cancelled) { try wide.slicingFourState(offset: 0, width: wide.width, context: &cancelled) }
        #expect(throws: LogicKernelError.cancelled) { try wide.shiftingFourState(left: false, amount: value([0]), context: &cancelled) }
        #expect(throws: LogicKernelError.cancelled) { try one.selectingFourState(ifTrue: wide, ifFalse: wide, context: &cancelled) }
        let before = run.usage[.allocationBytes]
        _ = try wide.resizedFourState(to: wide.width, signExtend: false, context: &run)
        _ = try wide.slicingFourState(offset: 0, width: wide.width, context: &run)
        _ = try wide.shiftingFourState(left: false, amount: value([0]), context: &run)
        _ = try one.selectingFourState(ifTrue: wide, ifFalse: wide, context: &run)
        #expect(run.usage[.allocationBytes] == before)
    }

    @Test func twoStateConversionPreservesKnownBitsAndClearsUnknownLimbs() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        for width in [1, 4, 65, 129] {
            for offset in 0..<4 {
                let input = (0..<width).map { UInt8(($0 + offset) % 4) }
                let original = try value(input)
                let converted = try original.convertedToTwoState(context: &run)
                #expect(converted.isTwoState)
                #expect(try bits(converted) == input.map { $0 == 1 ? 1 : 0 })
                #expect(try bits(original) == input)
            }
        }
        let unknown = try value([2,3])
        var cancelled = try context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try unknown.convertedToTwoState(context: &cancelled) }
        var small = try context(storage: 1)
        #expect(throws: LogicKernelError.self) { try unknown.convertedToTwoState(context: &small) }
    }
}
