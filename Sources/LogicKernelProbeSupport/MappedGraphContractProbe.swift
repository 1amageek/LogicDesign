import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public nonisolated func exerciseMappedGraphContract() throws(LogicKernelError) {
    var run = LogicKernelContext(limits: try .init(maximums:
        Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })), control: MappedGraphProbeControl())
    var function = try LogicBooleanFunctionBuilder(inputCount: 2, nodeCapacity: 2, context: &run)
    let input = try function.append(.input(0), context: &run)
    let output = try function.append(.invert(input), context: &run)
    let f = try function.finish(output: output, context: &run)
    let source: ArtifactID
    do { source = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "cd", count: 32)), byteCount: 1) }
    catch { throw .invalidInput("Mapped probe source identity is invalid") }
    var cell = try LogicTechnologyCellBuilder(id: mappedProbeID(100), name: "INV", pinCapacity: 2, context: &run)
    _ = try cell.append(.init(id: mappedProbeID(101), name: "A", direction: .input), context: &run)
    _ = try cell.append(.init(id: mappedProbeID(102), name: "Y", direction: .output, function: f), context: &run)
    let definition = try cell.finish(area: 1, context: &run)
    var libraryBuilder = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 2, context: &run)
    _ = try libraryBuilder.append(definition, context: &run)
    let library = try libraryBuilder.finish(source: source, context: &run)
    var builder = try MappedGateBuilder(library: library,
        capacity: .init(nets: 2, instances: 1, pinConnections: 2, ports: 2, portBits: 2), context: &run)
    let y = try builder.addNet(.init(id: mappedProbeID(1), driver: .instanceOutput(.init(0), .init(1))), context: &run)
    let a = try builder.addNet(.init(id: mappedProbeID(2), driver: .input), context: &run)
    _ = try builder.addInstance(id: mappedProbeID(3), cell: .init(0), pinNets: [a, y], context: &run)
    try builder.addPort(id: mappedProbeID(4), direction: .input, nets: [a], context: &run)
    try builder.addPort(id: mappedProbeID(5), direction: .output, nets: [y], context: &run)
    let design = try builder.finish(context: &run)
    try design.validateLibrary(library, context: &run)
    let ordered = design.withTables { nets, instances, pins, ports, bits, steps in
        nets.count == 2 && instances.count == 1 && pins.count == 2 && ports.count == 2 && bits.count == 2
            && steps.count == 2 && steps[0] == .net(a) && steps[1] == .net(y)
    }
    guard ordered else { throw .invalidModel("Mapped connectivity or connection-derived order changed") }
    var cycle = try MappedGateBuilder(library: library,
        capacity: .init(nets: 1, instances: 1, pinConnections: 2, ports: 0, portBits: 0), context: &run)
    let loop = try cycle.addNet(.init(id: mappedProbeID(1), driver: .instanceOutput(.init(0), .init(1))), context: &run)
    _ = try cycle.addInstance(id: mappedProbeID(2), cell: .init(0), pinNets: [loop, loop], context: &run)
    do throws(LogicKernelError) {
        _ = try cycle.finish(context: &run)
        throw .unsupported("Mapped transparent cycle was accepted")
    } catch .invalidModel {} catch { throw error }
    for latch in [false, true] {
        var outputFunction = try LogicBooleanFunctionBuilder(inputCount: 5, nodeCapacity: 1, context: &run)
        let q = try outputFunction.append(.input(4), context: &run)
        let qFunction = try outputFunction.finish(output: q, context: &run)
        var dataFunction = try LogicBooleanFunctionBuilder(inputCount: 5, nodeCapacity: 1, context: &run)
        let d = try dataFunction.append(.input(0), context: &run)
        let dFunction = try dataFunction.finish(output: d, context: &run)
        var sequential = try LogicTechnologyCellBuilder(id: mappedProbeID(200), name: "SEQ", pinCapacity: 4, context: &run)
        for pin in 0..<3 {
            _ = try sequential.append(.init(id: mappedProbeID(UInt64(201 + pin)), name: "I\(pin)", direction: .input), context: &run)
        }
        _ = try sequential.append(.init(id: mappedProbeID(204), name: "Q", direction: .output, function: qFunction), context: &run)
        let control: LogicCellStateDefinition.Control = latch ? .latch(gate: .init(1), activeHigh: true)
            : .flipFlop(clock: .init(1), risingEdge: true)
        let seqCell = try sequential.finish(area: 1, state: .init(control: control, nextState: dFunction,
            asynchronousReset: .init(pin: .init(2), activeHigh: false, value: false)), context: &run)
        var seqLibraryBuilder = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 4, context: &run)
        _ = try seqLibraryBuilder.append(seqCell, context: &run)
        let seqLibrary = try seqLibraryBuilder.finish(source: source, context: &run)
        var feedback = try MappedGateBuilder(library: seqLibrary,
            capacity: .init(nets: 3, instances: 1, pinConnections: 4, ports: 1, portBits: 1), context: &run)
        let qNet = try feedback.addNet(.init(id: mappedProbeID(1), driver: .instanceOutput(.init(0), .init(3))), context: &run)
        let clock = try feedback.addNet(.init(id: mappedProbeID(2), driver: .input), context: &run)
        let reset = try feedback.addNet(.init(id: mappedProbeID(3), driver: .constant(true)), context: &run)
        _ = try feedback.addInstance(id: mappedProbeID(4), cell: .init(0), pinNets: [qNet, clock, reset, qNet],
            stateID: mappedProbeID(5), context: &run)
        try feedback.addPort(id: mappedProbeID(6), direction: .input, nets: [clock], context: &run)
        if latch {
            do throws(LogicKernelError) {
                _ = try feedback.finish(context: &run)
                throw .unsupported("Transparent latch feedback was accepted")
            } catch .invalidModel {} catch { throw error }
        } else {
            let ffDesign = try feedback.finish(context: &run)
            guard ffDesign.stateCount == 1 else { throw .invalidModel("FF feedback lost its state") }
        }
    }
}

private nonisolated func mappedProbeID(_ value: UInt64) throws(LogicKernelError) -> DesignEntityID {
    do { return try .init(rawValue: value) }
    catch { throw .invalidInput("Mapped probe entity identity is invalid") }
}

private struct MappedGraphProbeControl: LogicRunControlling {
    func checkpoint() throws(LogicKernelError) {}
}
