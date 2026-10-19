import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public nonisolated func exerciseMappedRealizationContract() throws(LogicKernelError) {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }))
    var run = LogicKernelContext(limits: limits, control: RealizationProbeControl())
    let validator: any MappedGateRealizationValidating = NativeMappedGateRealizationValidator()
    let source: ArtifactID
    do { source = try .init(digest: .init(algorithm: .sha256,
        hexadecimalValue: String(repeating: "ab", count: 32)), byteCount: 1) }
    catch { throw .invalidInput("Realization probe source identity is invalid") }
    var libraryBuilder = try LogicTechnologyLibraryBuilder(cellCapacity: 4, totalPinCapacity: 8, context: &run)
    for index in 0..<4 {
        let sequential = index >= 2
        let count = sequential ? 3 : 1
        var function = try LogicBooleanFunctionBuilder(inputCount: sequential ? 4 : 1,
            nodeCapacity: 1, context: &run)
        let output = try function.append(sequential ? .input(3) : .constant(index == 1), context: &run)
        let outputFunction = try function.finish(output: output, context: &run)
        let base = UInt64(100 + index * 10)
        var cell = try LogicTechnologyCellBuilder(id: realizationProbeID(base), name: "C\(index)",
            pinCapacity: count, context: &run)
        if sequential {
            _ = try cell.append(.init(id: realizationProbeID(base + 1), name: "D", direction: .input), context: &run)
            _ = try cell.append(.init(id: realizationProbeID(base + 2), name: "C", direction: .input), context: &run)
        }
        _ = try cell.append(.init(id: realizationProbeID(base + UInt64(count)), name: "Q",
            direction: .output, function: outputFunction), context: &run)
        let state: LogicCellStateDefinition?
        if sequential {
            var data = try LogicBooleanFunctionBuilder(inputCount: 4, nodeCapacity: 1, context: &run)
            let input = try data.append(.input(0), context: &run)
            let next = try data.finish(output: input, context: &run)
            state = .init(control: index == 2 ? .flipFlop(clock: .init(1), risingEdge: true)
                : .latch(gate: .init(1), activeHigh: true), nextState: next)
        } else { state = nil }
        _ = try libraryBuilder.append(cell.finish(area: 1, state: state, context: &run), context: &run)
    }
    let library = try libraryBuilder.finish(source: source, context: &run)
    for index in 2..<4 {
        for initial: Bool? in [nil, false, true] {
            var builder = try MappedGateBuilder(library: library, capacity: .init(nets: 3, instances: 1,
                pinConnections: 3, ports: 2, portBits: 3), context: &run)
            let d = try builder.addNet(.init(id: realizationProbeID(1), driver: .input), context: &run)
            let c = try builder.addNet(.init(id: realizationProbeID(2), driver: .input), context: &run)
            let q = try builder.addNet(.init(id: realizationProbeID(3),
                driver: .instanceOutput(.init(0), .init(2))), context: &run)
            _ = try builder.addInstance(id: realizationProbeID(4), cell: .init(index), pinNets: [d, c, q],
                stateID: realizationProbeID(5), initialValue: initial, context: &run)
            try builder.addPort(id: realizationProbeID(6), direction: .input, nets: [d, c], context: &run)
            try builder.addPort(id: realizationProbeID(7), direction: .output, nets: [q], context: &run)
            let graph = try builder.finish(context: &run)
            for policy in [MappedGateRealizationPolicy.standardNetlist, .physicalCells] {
                if initial == nil { try validator.validate(graph, policy: policy, context: &run) }
                else {
                    do throws(LogicKernelError) {
                        try validator.validate(graph, policy: policy, context: &run)
                        throw .invalidModel("Specified physical startup was accepted without a mechanism")
                    } catch .unsupported {} catch { throw error }
                }
            }
            guard graph.withTables({ _, instances, _, _, _, _ in instances[0].initialValue == initial }) else {
                throw .invalidModel("Realization validation changed the abstract initial demand")
            }
        }
    }
    for value in [false, true] {
        var logical = try MappedGateBuilder(library: library, capacity: .init(nets: 1, instances: 0,
            pinConnections: 0, ports: 1, portBits: 1), context: &run)
        let net = try logical.addNet(.init(id: realizationProbeID(1), driver: .constant(value)), context: &run)
        try logical.addPort(id: realizationProbeID(2), direction: .output, nets: [net], context: &run)
        let logicalGraph = try logical.finish(context: &run)
        try validator.validate(logicalGraph, policy: .standardNetlist, context: &run)
        do throws(LogicKernelError) {
            try validator.validate(logicalGraph, policy: .physicalCells, context: &run)
            throw .invalidModel("Physical constant was accepted without an actual tie cell")
        } catch .unsupported {} catch { throw error }
        var physical = try MappedGateBuilder(library: library, capacity: .init(nets: 1, instances: 1,
            pinConnections: 1, ports: 1, portBits: 1), context: &run)
        let output = try physical.addNet(.init(id: realizationProbeID(1),
            driver: .instanceOutput(.init(0), .init(0))), context: &run)
        _ = try physical.addInstance(id: realizationProbeID(2), cell: .init(value ? 1 : 0),
            pinNets: [output], context: &run)
        try physical.addPort(id: realizationProbeID(3), direction: .output, nets: [output], context: &run)
        let physicalGraph = try physical.finish(context: &run)
        try validator.validate(physicalGraph, policy: .physicalCells, context: &run)
        let cell = try library.cell(at: .init(value ? 1 : 0))
        guard let function = try cell.pin(at: .init(0)).function,
              function.withOperations({ $0[function.output.rawValue] == .constant(value) }) else {
            throw .invalidModel("Actual tie cell lost its exact constant function")
        }
        var maximums = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })
        maximums[.workUnits] = 1
        var bounded = LogicKernelContext(limits: try .init(maximums: maximums), control: RealizationProbeControl())
        do throws(LogicKernelError) {
            try validator.validate(physicalGraph, policy: .physicalCells, context: &bounded)
            throw .invalidModel("Realization validation bypassed cumulative work admission")
        } catch .resourceLimit(let resource, _, _) {
            guard resource == .workUnits else { throw .invalidModel("Unexpected realization limit category") }
        } catch { throw error }
        let cancellation = LogicCancellationSource()
        var cancelled = LogicKernelContext(limits: limits, control: cancellation)
        cancellation.cancel()
        do throws(LogicKernelError) {
            try validator.validate(physicalGraph, policy: .standardNetlist, context: &cancelled)
            throw .invalidModel("Realization validation ignored cancellation")
        } catch .cancelled {} catch { throw error }
    }
}

private nonisolated func realizationProbeID(_ value: UInt64) throws(LogicKernelError) -> DesignEntityID {
    do { return try .init(rawValue: value) }
    catch { throw .invalidInput("Realization probe identity is invalid") }
}

private struct RealizationProbeControl: LogicRunControlling {
    func checkpoint() throws(LogicKernelError) {}
}
