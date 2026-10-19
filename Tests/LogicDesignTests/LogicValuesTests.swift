import Testing
import LogicIR
import LogicKernelCore

@Suite(.timeLimit(.minutes(1)))
struct LogicValuesTests {
    private struct Control: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) {}
    }

    @Test func arbitraryWidthPlanesRetainExactBits() throws {
        let vector = try LogicFourStateVector(
            width: LogicBitWidth(129), valueWords: [1, 0, 1], unknownWords: [0, .max, 0]
        )
        #expect(try vector.bit(at: 0) == .one)
        #expect(try vector.bit(at: 63) == .zero)
        #expect(try vector.bit(at: 64) == .unknown)
        #expect(try vector.bit(at: 127) == .unknown)
        #expect(try vector.bit(at: 128) == .one)
        #expect(!vector.isTwoState)
        if #available(macOS 26.0, *) {
            #expect(vector.withPlanes { values, unknowns in
                values.count == 3 && values[2] == 1 && unknowns[1] == .max
            })
        } else { Issue.record("Span runtime verification requires macOS 26") }
    }

    @Test func constructorsRejectMalformedStorageAndIndices() throws {
        #expect(throws: LogicKernelError.self) { try LogicBitWidth(0) }
        #expect(throws: LogicKernelError.self) {
            try LogicFourStateVector(width: LogicBitWidth(1), valueWords: [.max], unknownWords: [0])
        }
        #expect(throws: LogicKernelError.self) {
            try LogicFourStateVector(width: LogicBitWidth(65), valueWords: [0], unknownWords: [0, 0])
        }
        let vector = try LogicFourStateVector(width: LogicBitWidth(1), valueWords: [0], unknownWords: [0])
        #expect(throws: LogicKernelError.self) { try vector.bit(at: -1) }
        #expect(throws: LogicKernelError.self) { try vector.bit(at: 1) }
        let width = try LogicBitWidth(Int.max)
        #expect(width.wordCount > 0)
        #expect(throws: LogicKernelError.self) {
            try LogicFourStateVector(width: width, valueWords: [], unknownWords: [])
        }
        #expect(throws: LogicBitVectorError.self) {
            try LogicBitVector(width: Int.max, bytes: [])
        }
    }

    @Test func repeatedValuesCheckBudgetsBeforeAllocation() throws {
        var maximums = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100)) })
        maximums[.bitWidth] = 256
        var context = LogicKernelContext(limits: try LogicKernelLimits(maximums: maximums), control: Control())
        let vector = try LogicFourStateVector(repeating: .highImpedance, width: LogicBitWidth(129), context: &context)
        #expect(try vector.bit(at: 128) == .highImpedance)
        #expect(context.usage[.managedStorageBytes] == 48)
        let before = context.usage
        do {
            _ = try LogicFourStateVector(repeating: .one, width: LogicBitWidth(Int.max), context: &context)
            Issue.record("Expected width admission failure")
        } catch {
            #expect(error == .resourceLimit(resource: .bitWidth, limit: 256, requested: UInt64(Int.max)))
        }
        #expect(context.usage == before)
    }

    @Test func immutableStorageSurvivesCallerMutation() throws {
        var values: [UInt64] = [1]
        let vector = try LogicFourStateVector(width: LogicBitWidth(1), valueWords: values, unknownWords: [0])
        values[0] = 0
        #expect(try vector.bit(at: 0) == .one)
    }

    @Test func immutableValuesSupportConcurrentReadersAndCallerMutation() async throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var words: [UInt64] = [1, 0, 1]
        let vector = try LogicFourStateVector(width: LogicBitWidth(129), valueWords: words, unknownWords: [0, 0, 0])
        let verified = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<32 {
                group.addTask { vector.withPlanes { values, unknowns in values[2] == 1 && unknowns[0] == 0 } }
            }
            words[2] = 0
            var verified = 0
            for await result in group { if result { verified += 1 } }
            return verified
        }
        #expect(verified == 32)
        #expect(words[2] == 0)
        #expect(try vector.bit(at: 128) == .one)
    }

    @Test func fourStateLogicDoesNotTreatUnknownAsDontCare() {
        let bits: [LogicBit] = [.zero, .one, .unknown, .highImpedance]
        let andRows: [[LogicBit]] = [
            [.zero, .zero, .zero, .zero], [.zero, .one, .unknown, .unknown],
            [.zero, .unknown, .unknown, .unknown], [.zero, .unknown, .unknown, .unknown]
        ]
        let orRows: [[LogicBit]] = [
            [.zero, .one, .unknown, .unknown], [.one, .one, .one, .one],
            [.unknown, .one, .unknown, .unknown], [.unknown, .one, .unknown, .unknown]
        ]
        for lhs in bits.indices {
            for rhs in bits.indices {
                #expect(bits[lhs].and(bits[rhs]) == andRows[lhs][rhs])
                #expect(bits[lhs].or(bits[rhs]) == orRows[lhs][rhs])
                let expected: LogicBit = lhs < 2 && rhs < 2 ? (lhs == rhs ? .zero : .one) : .unknown
                #expect(bits[lhs].xor(bits[rhs]) == expected)
            }
        }
        #expect(LogicBit.unknown.selecting(ifTrue: .one, ifFalse: .one) == .one)
        #expect(LogicBit.unknown.selecting(ifTrue: .one, ifFalse: .zero) == .unknown)
        #expect(LogicBit.highImpedance.inverted == .unknown)
    }
}
