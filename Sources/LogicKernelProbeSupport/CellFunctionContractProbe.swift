import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public nonisolated func exerciseCellFunctionContract() throws(LogicKernelError) {
    var context = LogicKernelContext(
        limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, UInt64(1_000_000)) })), control: CellFunctionProbeControl())
    var builder = try LogicBooleanFunctionBuilder(inputCount: 2, nodeCapacity: 4, context: &context)
    let b = try builder.append(.input(1), context: &context)
    let a = try builder.append(.input(0), context: &context)
    let and = try builder.append(.and(a, b), context: &context)
    let nand = try builder.append(.invert(and), context: &context)
    let function = try builder.finish(output: nand, context: &context)
    for inputs in 0..<4 {
        let result = function.withOperations { operations in
            var values = [Bool](repeating: false, count: operations.count)
            for index in operations.indices {
                switch operations[index] {
                case .constant(let value): values[index] = value
                case .input(let slot): values[index] = inputs & (1 << slot) != 0
                case .invert(let node): values[index] = !values[node.rawValue]
                case .and(let a, let b): values[index] = values[a.rawValue] && values[b.rawValue]
                case .or(let a, let b): values[index] = values[a.rawValue] || values[b.rawValue]
                case .xor(let a, let b): values[index] = values[a.rawValue] != values[b.rawValue]
                }
            }
            return values[function.output.rawValue]
        }
        guard result == (inputs != 3) else { throw .invalidModel("Published NAND function changed meaning") }
    }
    var invalid = try LogicBooleanFunctionBuilder(inputCount: 1, nodeCapacity: 2, context: &context)
    do throws(LogicKernelError) {
        _ = try invalid.append(.invert(.init(0)), context: &context)
        throw .unsupported("Boolean function accepted a forward edge")
    } catch .invalidModel {} catch { throw error }
    let node = try invalid.append(.input(0), context: &context)
    guard node.rawValue == 0 else { throw .invalidModel("Failed Boolean append mutated storage") }
    _ = try invalid.finish(output: node, context: &context)
}

private struct CellFunctionProbeControl: LogicRunControlling {
    func checkpoint() throws(LogicKernelError) {}
}
