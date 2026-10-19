import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public nonisolated func exerciseTechnologyLibraryContract() throws(LogicKernelError) {
    var run = LogicKernelContext(limits: try LogicKernelLimits(maximums:
        Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })),
        control: TechnologyLibraryProbeControl())
    let cellID: DesignEntityID
    let inputID: DesignEntityID
    let outputID: DesignEntityID
    let source: ArtifactID
    do {
        cellID = try .init(rawValue: 1); inputID = try .init(rawValue: 2); outputID = try .init(rawValue: 3)
        source = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "ab", count: 32)), byteCount: 42)
    } catch { throw .invalidInput("Probe fixture identity construction failed") }
    var function = try LogicBooleanFunctionBuilder(inputCount: 2, nodeCapacity: 2, context: &run)
    let a = try function.append(.input(0), context: &run)
    let notA = try function.append(.invert(a), context: &run)
    let f = try function.finish(output: notA, context: &run)
    var cell = try LogicTechnologyCellBuilder(id: cellID, name: "INV", pinCapacity: 2, context: &run)
    _ = try cell.append(.init(id: inputID, name: "A", direction: .input), context: &run)
    do throws(LogicKernelError) {
        _ = try cell.append(.init(id: inputID, name: "BAD", direction: .output, function: f), context: &run)
        throw .unsupported("Cell accepted a duplicate pin identity")
    } catch .invalidModel {} catch { throw error }
    let y = try cell.append(.init(id: outputID, name: "Y", direction: .output, function: f), context: &run)
    guard y.rawValue == 1 else { throw .invalidModel("Failed pin append mutated the builder") }
    let value = try cell.finish(area: 1.5, context: &run)
    var library = try LogicTechnologyLibraryBuilder(cellCapacity: 2, totalPinCapacity: 4, context: &run)
    _ = try library.append(value, context: &run)
    do throws(LogicKernelError) {
        _ = try library.append(value, context: &run)
        throw .unsupported("Library accepted a duplicate cell")
    } catch .invalidModel {} catch { throw error }
    let published = try library.finish(source: source, context: &run)
    let actual = try published.cell(at: .init(0))
    guard published.source == source, published.cellCount == 1, actual.pinCount == 2,
          actual.area == 1.5, actual.withPins({ $0[0].id }) == inputID,
          actual.withPins({ $0[1].function?.output }) == notA else {
        throw .invalidModel("Library publication changed cell binding")
    }
}

private struct TechnologyLibraryProbeControl: LogicRunControlling {
    func checkpoint() throws(LogicKernelError) {}
}
