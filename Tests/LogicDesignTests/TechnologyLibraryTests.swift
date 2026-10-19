import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicKernelProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct TechnologyLibraryTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(storage: UInt64 = 1_000_000, work: UInt64 = 1_000_000,
                         control: any LogicRunControlling = Control()) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.workUnits] = work
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    private func id(_ value: UInt64) throws -> DesignEntityID { try .init(rawValue: value) }
    private func source() throws -> ArtifactID {
        try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "12", count: 32)), byteCount: 2048)
    }
    private func function(slots: Int, input: Int?, invert: Bool = false, context: inout LogicKernelContext)
        throws -> LogicBooleanFunction {
        var builder = try LogicBooleanFunctionBuilder(inputCount: slots, nodeCapacity: 2, context: &context)
        var output = try builder.append(input.map { .input($0) } ?? .constant(true), context: &context)
        if invert { output = try builder.append(.invert(output), context: &context) }
        return try builder.finish(output: output, context: &context)
    }
    @available(macOS 26.0, *)
    private func evaluate(_ function: LogicBooleanFunction, bits: Int) -> Bool {
        function.withOperations { operations in
            var values = [Bool](repeating: false, count: operations.count)
            for index in operations.indices {
                switch operations[index] {
                case .constant(let value): values[index] = value
                case .input(let slot): values[index] = bits & (1 << slot) != 0
                case .invert(let a): values[index] = !values[a.rawValue]
                case .and(let a, let b): values[index] = values[a.rawValue] && values[b.rawValue]
                case .or(let a, let b): values[index] = values[a.rawValue] || values[b.rawValue]
                case .xor(let a, let b): values[index] = values[a.rawValue] != values[b.rawValue]
                }
            }
            return values[function.output.rawValue]
        }
    }
    @available(macOS 26.0, *)
    private func cell(base: UInt64, name: String, context: inout LogicKernelContext) throws -> LogicTechnologyCell {
        let f = try function(slots: 2, input: 0, invert: true, context: &context)
        var builder = try LogicTechnologyCellBuilder(id: id(base), name: name, pinCapacity: 2, context: &context)
        _ = try builder.append(.init(id: id(base + 1), name: "A", direction: .input), context: &context)
        _ = try builder.append(.init(id: id(base + 2), name: "Y", direction: .output, function: f), context: &context)
        return try builder.finish(area: 1.25, context: &context)
    }

    @Test func publishedLibraryBindsFunctionsToExactPinsAndSource() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        try exerciseTechnologyLibraryContract()
        var run = try context()
        let first = try cell(base: 100, name: "INV", context: &run)
        let second = try cell(base: 200, name: "OTHER", context: &run)
        var builder = try LogicTechnologyLibraryBuilder(cellCapacity: 2, totalPinCapacity: 4, context: &run)
        #expect(try builder.append(second, context: &run).rawValue == 0)
        #expect(try builder.append(first, context: &run).rawValue == 1)
        let source = try source()
        let library = try builder.finish(source: source, context: &run)
        #expect(library.source == source && library.cellCount == 2)
        #expect(try library.cell(at: .init(1)).id == id(100))
        #expect(try library.cell(at: .init(1)).pin(at: .init(0)).name == "A")
        #expect(library.withCells { $0[0].name } == "OTHER")
        #expect(first.withPins { $0[1].function?.inputCount } == 2)
        for bits in 0..<4 {
            let output = try #require(first.pin(at: .init(1)).function)
            #expect(evaluate(output, bits: bits) == (bits & 1 == 0))
        }
        let constant = try function(slots: 1, input: nil, context: &run)
        var tie = try LogicTechnologyCellBuilder(id: id(400), name: "TIE", pinCapacity: 1, context: &run)
        _ = try tie.append(.init(id: id(401), name: "Y", direction: .output, function: constant), context: &run)
        let tied = try tie.finish(area: 0, context: &run)
        #expect(evaluate(try #require(tied.pin(at: .init(0)).function), bits: 0))
        for index in [-1, 2, Int.max] {
            #expect(throws: LogicKernelError.self) { try library.cell(at: .init(index)) }
            #expect(throws: LogicKernelError.self) { try first.pin(at: .init(index)) }
        }
        enum BorrowFailure: Error { case expected }
        #expect(throws: BorrowFailure.expected) {
            try library.withCells { _ throws(BorrowFailure) in throw .expected }
        }
    }

    @Test func stateSlotAndControlPolarityRemainExplicit() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        for latch in [false, true] {
            for positive in [false, true] {
                let q = try function(slots: 6, input: 5, context: &run)
                let qn = try function(slots: 6, input: 5, invert: true, context: &run)
                let d = try function(slots: 6, input: 0, context: &run)
                var builder = try LogicTechnologyCellBuilder(id: id(100), name: "SEQ", pinCapacity: 5, context: &run)
                for (index, name) in ["D", "C", "R"].enumerated() {
                    _ = try builder.append(.init(id: id(UInt64(index + 1)), name: name, direction: .input), context: &run)
                }
                _ = try builder.append(.init(id: id(4), name: "Q", direction: .output, function: q), context: &run)
                _ = try builder.append(.init(id: id(5), name: "QN", direction: .output, function: qn), context: &run)
                let control: LogicCellStateDefinition.Control = latch ? .latch(gate: .init(1), activeHigh: positive)
                    : .flipFlop(clock: .init(1), risingEdge: positive)
                let reset = LogicCellStateDefinition.AsynchronousReset(pin: .init(2), activeHigh: !positive, value: positive)
                let cell = try builder.finish(area: 0, state: .init(control: control, nextState: d, asynchronousReset: reset), context: &run)
                #expect(cell.state?.control == control && cell.state?.asynchronousReset == reset)
                #expect(cell.withPins { $0[4].function?.output.rawValue } == 1)
                for bits in 0..<64 {
                    #expect(evaluate(try #require(cell.pin(at: .init(3)).function), bits: bits) == (bits & 32 != 0))
                    #expect(evaluate(try #require(cell.pin(at: .init(4)).function), bits: bits) == (bits & 32 == 0))
                    #expect(evaluate(try #require(cell.state).nextState, bits: bits) == (bits & 1 != 0))
                }
            }
        }
        #expect(run.usage[.states] == 4)
    }

    @Test func invalidFunctionsDirectionsAndControlsCannotPublish() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for scenario in 0..<10 {
            #expect(throws: LogicKernelError.self) {
                var run = try context()
                let slots = scenario == 0 ? 1 : (scenario >= 4 ? 4 : 3)
                let output = try function(slots: slots, input: scenario == 1 ? 2 : 0, context: &run)
                let data = try function(slots: 4, input: 0, context: &run)
                var builder = try LogicTechnologyCellBuilder(id: id(100), name: "BAD", pinCapacity: 3, context: &run)
                _ = try builder.append(.init(id: id(1), name: "D", direction: .input,
                                             function: scenario == 2 ? output : nil), context: &run)
                _ = try builder.append(.init(id: id(2), name: "C", direction: .input), context: &run)
                _ = try builder.append(.init(id: id(3), name: "Q", direction: .output,
                                             function: scenario == 3 ? nil : output), context: &run)
                let state: LogicCellStateDefinition?
                switch scenario {
                case 4: state = .init(control: .flipFlop(clock: .init(2), risingEdge: true), nextState: data)
                case 5: state = .init(control: .latch(gate: .init(-1), activeHigh: true), nextState: data)
                case 6: state = .init(control: .flipFlop(clock: .init(1), risingEdge: true), nextState: data,
                                     asynchronousReset: .init(pin: .init(1), activeHigh: true, value: false))
                case 7: state = .init(control: .latch(gate: .init(1), activeHigh: true), nextState: data,
                                     asynchronousReset: .init(pin: .init(2), activeHigh: false, value: true))
                case 8: state = .init(control: .flipFlop(clock: .init(1), risingEdge: true),
                                     nextState: try function(slots: 4, input: 2, context: &run))
                case 9: state = .init(control: .latch(gate: .init(1), activeHigh: true),
                                     nextState: try function(slots: 3, input: 0, context: &run))
                default: state = nil
                }
                return try builder.finish(area: 1, state: state, context: &run)
            }
        }
        for area in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            #expect(throws: LogicKernelError.self) {
                var run = try context()
                var builder = try LogicTechnologyCellBuilder(id: id(100), name: "BAD", pinCapacity: 1, context: &run)
                let f = try function(slots: 1, input: nil, context: &run)
                _ = try builder.append(.init(id: id(1), name: "Y", direction: .output, function: f), context: &run)
                return try builder.finish(area: area, context: &run)
            }
        }
    }

    @Test func duplicateIdentitiesRefuseWithoutPartialAppend() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let first = try cell(base: 100, name: "A", context: &run)
        let sameName = try cell(base: 200, name: "A", context: &run)
        let collidingID = try cell(base: 101, name: "B", context: &run)
        let collidingPin = try cell(base: 99, name: "C", context: &run)
        let valid = try cell(base: 300, name: "D", context: &run)
        var builder = try LogicTechnologyLibraryBuilder(cellCapacity: 2, totalPinCapacity: 4, context: &run)
        _ = try builder.append(first, context: &run)
        for cell in [first, sameName, collidingID, collidingPin] {
            #expect(throws: LogicKernelError.self) { try builder.append(cell, context: &run) }
        }
        #expect(try builder.append(valid, context: &run).rawValue == 1)
        let result = try builder.finish(source: source(), context: &run)
        #expect(result.cellCount == 2)
        var pins = try LogicTechnologyCellBuilder(id: id(100), name: "X", pinCapacity: 2, context: &run)
        _ = try pins.append(.init(id: id(1), name: "D", direction: .input), context: &run)
        for (pinID, name) in [(UInt64(2), "D"), (1, "C"), (100, "C"), (2, "")] {
            #expect(throws: LogicKernelError.self) {
                try pins.append(.init(id: id(pinID), name: name, direction: .input), context: &run)
            }
        }
        let f = try function(slots: 2, input: nil, context: &run)
        #expect(try pins.append(.init(id: id(2), name: "Y", direction: .output, function: f), context: &run).rawValue == 1)
        #expect(try pins.finish(area: 0, context: &run).pinCount == 2)
    }

    @Test func capacitiesStorageCancellationAndEmptyModelsFailExplicitly() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for pair in [(0, 0), (1, -1), (Int.max, Int.max)] {
            #expect(throws: LogicKernelError.self) {
                var run = try context()
                _ = try LogicTechnologyLibraryBuilder(cellCapacity: pair.0, totalPinCapacity: pair.1, context: &run)
            }
        }
        var storage = try context(storage: 1)
        #expect(throws: LogicKernelError.self) {
            _ = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 1, context: &storage)
        }
        #expect(storage.usage[.allocationBytes] == 0)
        var cancelled = try context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) {
            _ = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 1, context: &cancelled)
        }
        #expect(throws: LogicKernelError.self) {
            var run = try context()
            let builder = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 1, context: &run)
            return try builder.finish(source: source(), context: &run)
        }
        #expect(throws: LogicKernelError.self) {
            var run = try context()
            var builder = try LogicTechnologyCellBuilder(id: id(100), name: "INPUTS", pinCapacity: 1, context: &run)
            _ = try builder.append(.init(id: id(1), name: "A", direction: .input), context: &run)
            return try builder.finish(area: 0, context: &run)
        }
        var run = try context()
        let cell = try cell(base: 100, name: "INV", context: &run)
        var small = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 1, context: &run)
        #expect(throws: LogicKernelError.self) { try small.append(cell, context: &run) }
        var work = try context(work: 1)
        #expect(throws: LogicKernelError.self) { try small.append(cell, context: &work) }
        var enormous = LogicKernelContext(limits: try LogicKernelLimits(maximums:
            Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64.max) })), control: Control())
        #expect(throws: LogicKernelError.self) {
            _ = try LogicTechnologyLibraryBuilder(cellCapacity: Int.max, totalPinCapacity: Int.max, context: &enormous)
        }
        #expect(throws: LogicKernelError.self) {
            _ = try LogicTechnologyCellBuilder(id: id(100), name: "HUGE", pinCapacity: Int.max, context: &enormous)
        }
        #expect(enormous.usage[.allocationBytes] == 0)
    }
}
