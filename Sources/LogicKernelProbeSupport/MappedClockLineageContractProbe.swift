import CircuiteFoundation
import LogicIR
import LogicKernelCore

/// Exercises actual function-derived clock branches without a proof or timing claim.
@available(macOS 26.0, *)
public nonisolated func exerciseMappedClockLineageContract() throws(LogicKernelError) {
    var context = LogicKernelContext(limits: try .init(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })), control: ClockProbeControl())
    let library = try clockLineageProbeLibrary(context: &context)
    for scenario in 0..<14 {
        let accepted = [0, 1, 2, 3, 8, 9, 10, 12].contains(scenario)
        do throws(LogicKernelError) {
            let design = try clockLineageProbeDesign(scenario: scenario, library: library, context: &context)
            guard accepted else { throw .invalidInput("Invalid clock branch was admitted") }
            try design.withStateClocks { clocks throws(LogicKernelError) in
                guard clocks.count == 2 else { throw .invalidModel("Clock table lost a state") }
                if scenario == 8 || scenario == 9 || scenario == 10 {
                    guard case .opaque = clocks[0].lineage, clocks[0].lineage == clocks[1].lineage else {
                        throw .invalidModel("Legacy shared opaque control changed")
                    }
                } else {
                    for index in clocks.indices {
                        guard case .primaryInput(let root, let inverted, let rising) = clocks[index].lineage,
                              root.rawValue == 0, rising, inverted == !clocks[index].risingEdge else {
                            throw .invalidModel("Actual function, parity or effective edge was lost")
                        }
                    }
                }
            }
        } catch .invalidModel where scenario == 7 {
        } catch .unsupported {
            guard !accepted else { throw .invalidModel("Valid clock branches were refused") }
        }
    }
}

@available(macOS 26.0, *)
public nonisolated func clockLineageProbeLibrary(context: inout LogicKernelContext)
    throws(LogicKernelError) -> LogicTechnologyLibrary {
    var library = try LogicTechnologyLibraryBuilder(cellCapacity: 6, totalPinCapacity: 18, context: &context)
    for index in 0..<6 {
        let sequential = index >= 4
        var function = try LogicBooleanFunctionBuilder(inputCount: sequential ? 4 : 3, nodeCapacity: 5, context: &context)
        let a = try function.append(.input(sequential ? 3 : 0), context: &context)
        let b = try function.append(.input(1), context: &context)
        let output: LogicBooleanNodeIndex
        switch index {
        case 0: output = try function.append(.and(a, a), context: &context)
        case 1: output = try function.append(.invert(a), context: &context)
        case 2: output = try function.append(.and(a, b), context: &context)
        case 3: output = try function.append(.constant(true), context: &context)
        default: output = a
        }
        let f = try function.finish(output: output, context: &context)
        let base = UInt64(100 + index * 10)
        // Deliberately misleading names: classification must use the actual output function.
        var cell = try LogicTechnologyCellBuilder(id: clockProbeID(base), name: "BUF_\(index)", pinCapacity: 3, context: &context)
        for pin in 0..<2 {
            _ = try cell.append(.init(id: clockProbeID(base + UInt64(pin) + 1), name: "I\(pin)", direction: .input), context: &context)
        }
        _ = try cell.append(.init(id: clockProbeID(base + 3), name: "Q", direction: .output, function: f), context: &context)
        let state: LogicCellStateDefinition?
        if sequential {
            var next = try LogicBooleanFunctionBuilder(inputCount: 4, nodeCapacity: 1, context: &context)
            let d = try next.append(.input(0), context: &context)
            state = .init(control: .flipFlop(clock: .init(1), risingEdge: index == 4),
                          nextState: try next.finish(output: d, context: &context))
        } else { state = nil }
        _ = try library.append(cell.finish(area: 1, state: state, context: &context), context: &context)
    }
    let source: ArtifactID
    do { source = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "ea", count: 32)), byteCount: 1) }
    catch { throw .invalidInput("Clock probe source identity is invalid") }
    return try library.finish(source: source, context: &context)
}

@available(macOS 26.0, *)
public nonisolated func clockLineageProbeDesign(scenario: Int, library: LogicTechnologyLibrary,
                                               context: inout LogicKernelContext)
    throws(LogicKernelError) -> MappedGateDesign {
    var builder = try MappedGateBuilder(library: library, capacity: .init(nets: 7, instances: 4,
        pinConnections: 12, ports: 2, portBits: 4), context: &context)
    for index in 0..<3 {
        _ = try builder.addNet(.init(id: clockProbeID(UInt64(index + 1)), driver: .input), context: &context)
    }
    for index in 0..<4 {
        _ = try builder.addNet(.init(id: clockProbeID(UInt64(index + 4)), driver: .instanceOutput(.init(index), .init(2))), context: &context)
    }
    let firstKind = scenario == 6 || scenario == 8 ? 2 : (scenario == 9 || scenario == 11 ? 3 : (scenario == 12 ? 1 : 0))
    _ = try builder.addInstance(id: clockProbeID(20), cell: .init(firstKind),
        pinNets: [.init(0), .init(1), .init(3)], context: &context)
    let secondKind = scenario == 1 || scenario == 2 || scenario == 5 || scenario == 12 ? 1 : 0
    let secondInput = scenario == 3 || scenario == 12 ? 3 : (scenario == 4 ? 1 : (scenario == 7 ? 4 : 0))
    _ = try builder.addInstance(id: clockProbeID(21), cell: .init(secondKind),
        pinNets: [.init(secondInput), .init(1), .init(4)], context: &context)
    let firstCarrier = scenario == 2 || scenario == 12 ? 0 : (scenario == 10 || scenario == 13 ? 5 : 3)
    let secondCarrier = scenario == 8 || scenario == 9 ? 3 : (scenario == 10 ? 5 : 4)
    _ = try builder.addInstance(id: clockProbeID(22), cell: .init(4), pinNets: [.init(2), .init(firstCarrier), .init(5)],
        stateID: clockProbeID(30), context: &context)
    _ = try builder.addInstance(id: clockProbeID(23), cell: .init(scenario == 1 || scenario == 2 ? 5 : 4),
        pinNets: [.init(2), .init(secondCarrier), .init(6)], stateID: clockProbeID(31), context: &context)
    try builder.addPort(id: clockProbeID(40), direction: .input, nets: [.init(0), .init(1), .init(2)], context: &context)
    try builder.addPort(id: clockProbeID(41), direction: .output, nets: [.init(6)], context: &context)
    return try builder.finish(context: &context)
}

private nonisolated func clockProbeID(_ value: UInt64) throws(LogicKernelError) -> DesignEntityID {
    do { return try .init(rawValue: value) }
    catch { throw .invalidInput("Clock probe entity identity is invalid") }
}
private struct ClockProbeControl: LogicRunControlling {
    func checkpoint() throws(LogicKernelError) {}
}
