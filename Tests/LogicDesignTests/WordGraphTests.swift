import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore

@Suite(.timeLimit(.minutes(1)))
struct WordGraphTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private func context() throws -> LogicKernelContext {
        LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(
            uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
        )), control: Control())
    }
    private func id(_ value: UInt64) throws -> DesignEntityID { try DesignEntityID(rawValue: value) }
    private func type(_ width: Int, signed: Bool = false) throws -> WordLogicType {
        WordLogicType(width: try LogicBitWidth(width), isSigned: signed)
    }
    private func operation(_ opcode: WordLogicOpcode, output: WordLogicType,
                           inputs: [WordLogicType]) throws -> WordLogicDesign {
        var context = try context()
        var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: inputs.count + 1,
            operands: inputs.count, ports: 0, states: 0), context: &context)
        _ = try builder.addNode(id: id(1), type: output, operation: .compute(opcode),
            inputs: inputs.indices.map { WordNodeIndex($0 + 1) }, context: &context)
        for index in inputs.indices {
            let value = try LogicFourStateVector(repeating: .zero, width: inputs[index].width, context: &context)
            _ = try builder.addNode(id: id(UInt64(index + 2)), type: inputs[index], operation: .constant(value), context: &context)
        }
        return try builder.finish(context: &context)
    }
    private func expectRejection(_ builder: consuming WordLogicBuilder, context: inout LogicKernelContext) {
        do { _ = try builder.finish(context: &context); Issue.record("Invalid word graph was published") }
        catch { }
    }

    @Test func resolvedWideArithmeticUsesConnectivityAndTypedBorrowing() throws {
        let graph = try operation(.add, output: type(129, signed: true), inputs: [type(129, signed: true), type(129, signed: true)])
        #expect(graph.nodeCount == 3)
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        #expect(graph.withTables { nodes, operands, _, _, order in
            order[2] == WordNodeIndex(0) && nodes[0].type.width.value == 129 && operands[1] == WordNodeIndex(2)
        })
        do {
            try graph.withNodes { (_: borrowing Span<WordLogicNode>) throws(LogicKernelError) -> Void in
                throw .cancelled
            }
            Issue.record("Borrow callback failure was lost")
        } catch { #expect(error == .cancelled) }
    }

    @Test func unresolvedSizingSignednessAndSelectionAreRejected() throws {
        let u8 = try type(8), s8 = try type(8, signed: true), u1 = try type(1)
        let cases: [(WordLogicOpcode, WordLogicType, [WordLogicType])] = [
            (.add, u8, [u8, try type(4)]), (.add, s8, [u8, u8]),
            (.equal, u8, [u8, u8]), (.lessThan, u1, [s8, u8]),
            (.signExtend, try type(16), [u8]), (.zeroExtend, try type(4), [u8]),
            (.slice(offset: 7), try type(2), [u8]), (.slice(offset: 0), s8, [u8]),
            (.select, u8, [try type(2), u8, u8]), (.select, u8, [try type(1, signed: true), u8, u8]),
            (.select, u8, [u1, u8, try type(16)]),
            (.concatenate, try type(12), [u8, u8]), (.concatenate, try type(16, signed: true), [u8, u8]),
            (.shiftRight(arithmetic: true), u8, [u8, s8])
        ]
        for (opcode, output, inputs) in cases {
            #expect(throws: LogicKernelError.self) { try operation(opcode, output: output, inputs: inputs) }
        }
    }

    @Test func explicitCastsAndBooleanConversionsAreAdmitted() throws {
        let u8 = try type(8), s8 = try type(8, signed: true), u1 = try type(1)
        for (opcode, output, inputs): (WordLogicOpcode, WordLogicType, [WordLogicType]) in [
            (.bitcast, u8, [s8]), (.signExtend, try type(129, signed: true), [s8]),
            (.zeroExtend, try type(129), [u8]), (.slice(offset: 7), u1, [u8]),
            (.concatenate, try type(16), [u8, s8]), (.logicalAnd, u1, [u8, s8]),
            (.shiftRight(arithmetic: true), s8, [s8, try type(128)]), (.select, s8, [u1, s8, s8])
        ] {
            let graph = try operation(opcode, output: output, inputs: inputs)
            #expect(graph.nodeCount == inputs.count + 1)
        }
    }

    @Test func constantsRejectUnknownsAndIncorrectWidths() throws {
        for mode in 0..<2 {
            var context = try context()
            var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 1, operands: 0, ports: 0, states: 0), context: &context)
            let value = try LogicFourStateVector(repeating: mode == 0 ? .unknown : .zero,
                                                width: LogicBitWidth(mode == 0 ? 8 : 4), context: &context)
            _ = try builder.addNode(id: id(1), type: type(8), operation: .constant(value), context: &context)
            expectRejection(builder, context: &context)
        }
    }

    @Test func wordStateFeedbackAndControlTypesAreChecked() throws {
        for mode in 0..<5 {
            var context = try context()
            var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 3, operands: 1,
                ports: 1, states: 1), context: &context)
            let clock = try builder.addNode(id: id(1), type: type(mode == 2 ? 2 : 1), operation: .input, context: &context)
            let q = try builder.addNode(id: id(2), type: type(8), operation: .state(WordStateIndex(0)), context: &context)
            let next = try builder.addNode(id: id(3), type: type(8), operation: .compute(.invert), inputs: [q], context: &context)
            let initial: LogicFourStateVector? = mode == 3 ? try LogicFourStateVector(repeating: .unknown, width: LogicBitWidth(8), context: &context) : nil
            let reset: WordReset? = mode == 4 ? try WordReset(signal: clock, activeHigh: true,
                value: LogicFourStateVector(repeating: .zero, width: LogicBitWidth(4), context: &context), kind: .asynchronous) : nil
            let control: WordStateControl = mode == 1 ? .latch(gate: clock, activeHigh: true, reset: nil)
                : .flipFlop(clock: clock, edge: .rising, enable: nil, reset: reset)
            _ = try builder.addState(WordLogicState(id: id(1), next: next, control: control, initialValue: initial), context: &context)
            try builder.addPort(WordLogicPort(id: id(1), direction: .input, value: clock), context: &context)
            if mode == 0 { let graph = try builder.finish(context: &context); #expect(graph.stateCount == 1) }
            else { expectRejection(builder, context: &context) }
        }
    }

    @Test func invalidReferencesIdentityPortsAndCapacitiesAreRejected() throws {
        for mode in 0..<3 {
            var context = try context()
            var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 1, operands: 1, ports: 1, states: 0), context: &context)
            if mode == 0 {
                _ = try builder.addNode(id: id(1), type: type(8), operation: .compute(.invert), inputs: [WordNodeIndex(99)], context: &context)
            } else {
                let input = try builder.addNode(id: id(1), type: type(8), operation: .input, context: &context)
                if mode == 2 { try builder.addPort(WordLogicPort(id: id(1), direction: .output, value: input), context: &context) }
            }
            expectRejection(builder, context: &context)
        }
        var context = try context()
        do {
            _ = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: Int.max, operands: 0, ports: 0, states: 0), context: &context)
            Issue.record("Expected pre-allocation rejection")
        } catch { }
        #expect(context.usage[.managedStorageBytes] == 0)
    }
}
