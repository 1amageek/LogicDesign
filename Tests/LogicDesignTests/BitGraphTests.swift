import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore

@Suite(.timeLimit(.minutes(1)))
struct BitGraphTests {
    @Test func voidBorrowCallbacksPreserveTheirExactTypedFailure() throws {
        var run = try context()
        let builder = try BitLogicBuilder(capacity: .init(nodes: 0, operands: 0, ports: 0, portBits: 0, states: 0), context: &run)
        let design = try builder.finish(context: &run)
        if #available(macOS 26.0, *) {
            func nodeFailure() throws(LogicKernelError) {
                try design.withNodes { _ throws(LogicKernelError) -> Void in throw .cancelled }
            }
            func tableFailure() throws(LogicKernelError) {
                try design.withTables { _, _, _, _, _, _ throws(LogicKernelError) -> Void in throw .deadlineExceeded }
            }
            #expect(throws: LogicKernelError.cancelled) { try nodeFailure() }
            #expect(throws: LogicKernelError.deadlineExceeded) { try tableFailure() }
        } else { Issue.record("Span verification requires macOS 26") }
    }
    private struct Control: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) {}
    }
    private struct Cancelled: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) { throw .cancelled }
    }
    private func context(control: any LogicRunControlling = Control()) throws -> LogicKernelContext {
        LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(
            uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
        )), control: control)
    }
    private func id(_ value: UInt64) throws -> DesignEntityID { try DesignEntityID(rawValue: value) }
    private func capacity(nodes: Int = 8, operands: Int = 16, states: Int = 0) throws -> BitGraphCapacity {
        try BitGraphCapacity(nodes: nodes, operands: operands, ports: 4, portBits: 8, states: states)
    }

    private func expectRejection(_ builder: consuming BitLogicBuilder, context: inout LogicKernelContext) {
        do { _ = try builder.finish(context: &context); Issue.record("Invalid graph was published") }
        catch { }
    }

    @Test func forwardReferencesUseConnectivityRatherThanIdentifiers() throws {
        var context = try context()
        var builder = try BitLogicBuilder(capacity: capacity(), context: &context)
        let output = try builder.addNode(id: id(1), operation: .and,
                                         inputs: [BitNodeIndex(2), BitNodeIndex(1)], context: &context)
        let first = try builder.addNode(id: id(900), operation: .input, context: &context)
        let second = try builder.addNode(id: id(2), operation: .input, context: &context)
        try builder.addPort(id: id(1), direction: .input, bits: [first, second], context: &context)
        try builder.addPort(id: id(2), direction: .output, bits: [output], context: &context)
        let design = try builder.finish(context: &context)
        #expect(design.nodeCount == 3)
        if #available(macOS 26.0, *) {
            #expect(design.withTables { nodes, operands, ports, bits, states, order in
                order[2] == output && nodes[0].operands == 0..<2 && operands[0] == second
                    && ports[0].bits.count == 2 && bits[2] == output && states.isEmpty
            })
        } else { Issue.record("Span verification requires macOS 26") }
    }

    @Test func invalidReferencesAndCombinationalCyclesAreRejected() throws {
        for reference in [-1, 0, 99] {
            var context = try context()
            var builder = try BitLogicBuilder(capacity: capacity(), context: &context)
            _ = try builder.addNode(id: id(1), operation: .invert, inputs: [BitNodeIndex(reference)], context: &context)
            let before = context.usage[.managedStorageBytes]
            expectRejection(builder, context: &context)
            #expect(context.usage[.managedStorageBytes] == before)
        }
    }

    @Test func arityAndFixedCapacityAreCheckedBeforeMutation() throws {
        var context = try context()
        var builder = try BitLogicBuilder(capacity: capacity(nodes: 1), context: &context)
        #expect(throws: LogicKernelError.self) {
            try builder.addNode(id: id(1), operation: .and, inputs: [], context: &context)
        }
        _ = try builder.addNode(id: id(1), operation: .constant(true), context: &context)
        #expect(throws: LogicKernelError.self) {
            try builder.addNode(id: id(2), operation: .constant(false), context: &context)
        }
        let design = try builder.finish(context: &context)
        #expect(design.nodeCount == 1)
    }

    @Test func inputCoverageAndUniqueIdentityAreRequired() throws {
        for duplicateID in [false, true] {
            var context = try context()
            var builder = try BitLogicBuilder(capacity: capacity(), context: &context)
            _ = try builder.addNode(id: id(1), operation: .input, context: &context)
            if duplicateID { _ = try builder.addNode(id: id(1), operation: .constant(false), context: &context) }
            expectRejection(builder, context: &context)
        }
        var context = try context()
        var builder = try BitLogicBuilder(capacity: capacity(), context: &context)
        let input = try builder.addNode(id: id(1), operation: .input, context: &context)
        try builder.addPort(id: id(1), direction: .input, bits: [input, input], context: &context)
        expectRejection(builder, context: &context)
    }

    @Test func flipFlopFeedbackIsLegalButTransparentLatchFeedbackIsRejected() throws {
        for latch in [false, true] {
            var context = try context()
            var builder = try BitLogicBuilder(capacity: capacity(states: 1), context: &context)
            let clock = try builder.addNode(id: id(1), operation: .input, context: &context)
            let q = try builder.addNode(id: id(2), operation: .state(BitStateIndex(0)), context: &context)
            let next = try builder.addNode(id: id(3), operation: .invert, inputs: [q], context: &context)
            let control: BitStateControl = latch ? .latch(gate: clock, activeHigh: true, reset: nil)
                : .flipFlop(clock: clock, edge: .rising, enable: nil, reset: nil)
            _ = try builder.addState(BitLogicState(id: id(1), next: next, control: control), context: &context)
            try builder.addPort(id: id(1), direction: .input, bits: [clock], context: &context)
            if latch {
                expectRejection(builder, context: &context)
            } else {
                let design = try builder.finish(context: &context)
                #expect(design.stateCount == 1)
                if #available(macOS 26.0, *) {
                    #expect(design.withTables { _, _, _, _, states, _ in states[0].initialValue == nil })
                }
            }
        }
    }

    @Test func stateProfilesRejectMixedClocksEdgesAndLatchResetKinds() throws {
        for mode in 0..<5 {
            var context = try context()
            var builder = try BitLogicBuilder(capacity: capacity(states: 2), context: &context)
            let clock = try builder.addNode(id: id(1), operation: .input, context: &context)
            let other = try builder.addNode(id: id(2), operation: .input, context: &context)
            let data = try builder.addNode(id: id(3), operation: .constant(true), context: &context)
            for index in 0..<2 {
                _ = try builder.addNode(id: id(UInt64(index + 4)), operation: .state(BitStateIndex(index)), context: &context)
                let control: BitStateControl
                if mode == 3 || mode == 4 {
                    control = .latch(gate: clock, activeHigh: index == 0 || mode == 4,
                        reset: mode == 4 ? BitReset(signal: other, activeHigh: true, value: false, kind: .synchronous) : nil)
                } else if mode == 2 && index == 1 {
                    control = .latch(gate: clock, activeHigh: true, reset: nil)
                } else {
                    control = .flipFlop(clock: mode == 0 && index == 1 ? other : clock,
                                      edge: mode == 1 && index == 1 ? .falling : .rising, enable: nil, reset: nil)
                }
                _ = try builder.addState(BitLogicState(id: id(UInt64(index + 1)), next: data, control: control), context: &context)
            }
            try builder.addPort(id: id(1), direction: .input, bits: [clock, other], context: &context)
            expectRejection(builder, context: &context)
        }
    }

    @Test func acyclicLatchChainIsAcceptedAndStateCoverageIsRequired() throws {
        for missing in [false, true] {
            var context = try context()
            var builder = try BitLogicBuilder(capacity: capacity(states: 2), context: &context)
            let gate = try builder.addNode(id: id(1), operation: .input, context: &context)
            let data = try builder.addNode(id: id(2), operation: .constant(true), context: &context)
            let first = try builder.addNode(id: id(3), operation: .state(BitStateIndex(0)), context: &context)
            if !missing { _ = try builder.addNode(id: id(4), operation: .state(BitStateIndex(1)), context: &context) }
            for index in 0..<2 {
                _ = try builder.addState(BitLogicState(id: id(UInt64(index + 1)), next: index == 0 ? data : first,
                    control: .latch(gate: gate, activeHigh: true, reset: nil)), context: &context)
            }
            try builder.addPort(id: id(1), direction: .input, bits: [gate], context: &context)
            if missing { expectRejection(builder, context: &context) }
            else { let design = try builder.finish(context: &context); #expect(design.stateCount == 2) }
        }
    }

    @Test func aSingleClockOrGateMayBeDerivedFromCombinationalLogic() throws {
        for latch in [false, true] {
            var context = try context()
            var builder = try BitLogicBuilder(capacity: capacity(states: 1), context: &context)
            let input = try builder.addNode(id: id(1), operation: .input, context: &context)
            let control = try builder.addNode(id: id(2), operation: .invert, inputs: [input], context: &context)
            let data = try builder.addNode(id: id(3), operation: .constant(true), context: &context)
            _ = try builder.addNode(id: id(4), operation: .state(BitStateIndex(0)), context: &context)
            let definition: BitStateControl = latch ? .latch(gate: control, activeHigh: true, reset: nil)
                : .flipFlop(clock: control, edge: .rising, enable: nil, reset: nil)
            _ = try builder.addState(BitLogicState(id: id(1), next: data, control: definition), context: &context)
            try builder.addPort(id: id(1), direction: .input, bits: [input], context: &context)
            let design = try builder.finish(context: &context)
            #expect(design.stateCount == 1)
        }
    }

    @Test func storageAdmissionAndCancellationDoNotPublishSuccess() throws {
        var cancelled = try context(control: Cancelled())
        do {
            _ = try BitLogicBuilder(capacity: capacity(), context: &cancelled)
            Issue.record("Expected cancellation")
        } catch let error as LogicKernelError { #expect(error == .cancelled) }
        var context = try context()
        do {
            _ = try BitLogicBuilder(capacity: capacity(nodes: Int.max), context: &context)
            Issue.record("Expected capacity rejection")
        } catch let error as LogicKernelError {
            if case .resourceLimit = error {} else { Issue.record("Unexpected capacity failure") }
        }
        #expect(context.usage[.managedStorageBytes] == 0)
    }
}
