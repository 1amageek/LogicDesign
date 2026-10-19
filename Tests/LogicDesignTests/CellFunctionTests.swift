import Testing
import LogicIR
import LogicKernelCore
import LogicKernelProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct CellFunctionTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(storage: UInt64 = 1_000_000, nodes: UInt64 = 100_000,
                         edges: UInt64 = 100_000, work: UInt64 = 100_000,
                         control: any LogicRunControlling = Control()) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.nodes] = nodes
        limits[.edges] = edges; limits[.workUnits] = work
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    @available(macOS 26.0, *)
    private func evaluate(_ function: LogicBooleanFunction, inputs: Int) -> Bool {
        function.withOperations { operations in
            var values = [Bool](repeating: false, count: operations.count)
            for index in operations.indices {
                switch operations[index] {
                case .constant(let value): values[index] = value
                case .input(let slot): values[index] = inputs & (1 << slot) != 0
                case .invert(let a): values[index] = !values[a.rawValue]
                case .and(let a, let b): values[index] = values[a.rawValue] && values[b.rawValue]
                case .or(let a, let b): values[index] = values[a.rawValue] || values[b.rawValue]
                case .xor(let a, let b): values[index] = values[a.rawValue] != values[b.rawValue]
                }
            }
            return values[function.output.rawValue]
        }
    }
    @Test func publishedFunctionsRetainMeaningAndPinPermutation() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        try exerciseCellFunctionContract()
        var run = try context()
        for permutation in [false, true] {
            for kind in 0..<6 {
                var builder = try LogicBooleanFunctionBuilder(inputCount: 2, nodeCapacity: 6, context: &run)
                let a = try builder.append(.input(permutation ? 1 : 0), context: &run)
                let b = try builder.append(.input(permutation ? 0 : 1), context: &run)
                let notB = try builder.append(.invert(b), context: &run)
                let output: LogicBooleanNodeIndex
                switch kind {
                case 0: output = try builder.append(.and(a, b), context: &run)
                case 1:
                    let and = try builder.append(.and(a, b), context: &run)
                    output = try builder.append(.invert(and), context: &run)
                case 2:
                    let or = try builder.append(.or(a, b), context: &run)
                    output = try builder.append(.invert(or), context: &run)
                case 3: output = try builder.append(.xor(a, b), context: &run)
                case 4: output = try builder.append(.and(a, notB), context: &run)
                default: output = try builder.append(.constant(true), context: &run)
                }
                let function = try builder.finish(output: output, context: &run)
                #expect(function.inputCount == 2)
                for inputs in 0..<4 {
                    let av = inputs & (permutation ? 2 : 1) != 0
                    let bv = inputs & (permutation ? 1 : 2) != 0
                    let expected = [av && bv, !(av && bv), !(av || bv), av != bv, av && !bv, true][kind]
                    #expect(evaluate(function, inputs: inputs) == expected)
                }
            }
        }
        for constant in [false, true] {
            var builder = try LogicBooleanFunctionBuilder(inputCount: 0, nodeCapacity: 1, context: &run)
            let node = try builder.append(.constant(constant), context: &run)
            let function = try builder.finish(output: node, context: &run)
            #expect(evaluate(function, inputs: 0) == constant)
        }
    }
    @Test func malformedInputsEdgesAndFailedMutationAreRejected() throws {
        var run = try context()
        var builder = try LogicBooleanFunctionBuilder(inputCount: 1, nodeCapacity: 3, context: &run)
        for operation in [LogicBooleanOperation.input(-1), .input(1), .invert(.init(0)), .and(.init(-1), .init(0))] {
            #expect(throws: LogicKernelError.self) { try builder.append(operation, context: &run) }
        }
        #expect(run.usage[.nodes] == 0 && run.usage[.edges] == 0)
        let zero = try builder.append(.input(0), context: &run)
        #expect(zero.rawValue == 0)
        #expect(throws: LogicKernelError.self) { try builder.append(.or(zero, .init(1)), context: &run) }
        let one = try builder.append(.and(zero, zero), context: &run)
        #expect(one.rawValue == 1 && run.usage[.edges] == 2)
        let two = try builder.append(.xor(zero, one), context: &run)
        #expect(throws: LogicKernelError.self) { try builder.append(.invert(two), context: &run) }
        let result = try builder.finish(output: two, context: &run)
        #expect(result.nodeCount == 3 && result.output == two)
        for output in [-1, 0, 1] {
            #expect(throws: LogicKernelError.self) {
                var innerRun = try context()
                let empty = try LogicBooleanFunctionBuilder(inputCount: 0, nodeCapacity: 1, context: &innerRun)
                return try empty.finish(output: .init(output), context: &innerRun)
            }
        }
        #expect(throws: LogicKernelError.self) {
            var innerRun = try context()
            var inner = try LogicBooleanFunctionBuilder(inputCount: 0, nodeCapacity: 1, context: &innerRun)
            _ = try inner.append(.constant(true), context: &innerRun)
            return try inner.finish(output: .init(1), context: &innerRun)
        }
    }
    @Test func budgetsCancellationAndTypedBorrowFailuresRemainExplicit() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for pair in [(-1, 1), (1, 0), (1, -1), (0, Int.max)] {
            #expect(throws: LogicKernelError.self) {
                var run = try context()
                _ = try LogicBooleanFunctionBuilder(inputCount: pair.0, nodeCapacity: pair.1, context: &run)
            }
        }
        var noStorage = try context(storage: 1)
        #expect(throws: LogicKernelError.self) {
            _ = try LogicBooleanFunctionBuilder(inputCount: 1, nodeCapacity: 2, context: &noStorage)
        }
        #expect(noStorage.usage[.allocationBytes] == 0)
        var run = try context(nodes: 2, edges: 1, work: 100)
        var builder = try LogicBooleanFunctionBuilder(inputCount: 1, nodeCapacity: 2, context: &run)
        let first = try builder.append(.input(0), context: &run)
        #expect(throws: LogicKernelError.self) { try builder.append(.and(first, first), context: &run) }
        let function = try builder.finish(output: first, context: &run)
        #expect(function.nodeCount == 1)
        enum BorrowError: Error { case expected }
        #expect(throws: BorrowError.expected) {
            try function.withOperations { _ throws(BorrowError) in throw .expected }
        }
        var cancelled = try context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) {
            _ = try LogicBooleanFunctionBuilder(inputCount: 1, nodeCapacity: 1, context: &cancelled)
        }
        var work = try context(work: 1)
        var partial = try LogicBooleanFunctionBuilder(inputCount: 0, nodeCapacity: 2, context: &work)
        let node = try partial.append(.constant(true), context: &work)
        #expect(throws: LogicKernelError.self) { try partial.append(.invert(node), context: &work) }
        #expect(try partial.finish(output: node, context: &work).nodeCount == 1)
    }
}
