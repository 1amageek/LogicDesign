import LogicKernelCore

public struct LogicBooleanFunctionBuilder: ~Copyable {
    private let inputCount: Int
    private let nodeCapacity: Int
    private var operations: [LogicBooleanOperation]

    public init(inputCount: Int, nodeCapacity: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard inputCount >= 0, nodeCapacity > 0 else {
            throw .invalidInput("Boolean function requires nonnegative inputs and positive node capacity")
        }
        try context.require(.nodes, amount: UInt64(nodeCapacity))
        try context.require(.edges, amount: UInt64(inputCount))
        let payload = UInt64(nodeCapacity).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicBooleanOperation>.stride))
        let total = payload.partialValue.addingReportingOverflow(UInt64(MemoryLayout<(Int, [LogicBooleanOperation], LogicBooleanNodeIndex)>.stride))
        guard !payload.overflow, !total.overflow else { throw .invalidInput("Boolean function capacity overflows") }
        _ = try context.reserveStorage(byteCount: total.partialValue)
        self.inputCount = inputCount; self.nodeCapacity = nodeCapacity
        operations = []; operations.reserveCapacity(nodeCapacity)
    }

    public mutating func append(_ operation: LogicBooleanOperation, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicBooleanNodeIndex {
        guard operations.count < nodeCapacity else { throw .invalidInput("Boolean function node capacity exhausted") }
        guard operation.isValid(nodeCount: operations.count, inputCount: inputCount) else {
            throw .invalidModel("Boolean function input or prior-node reference is invalid")
        }
        try context.observeBitWidth(1)
        try context.charge(.workUnits)
        try context.charge(.nodes)
        try context.charge(.edges, amount: operation.operandCount)
        let result = LogicBooleanNodeIndex(operations.count)
        operations.append(operation)
        return result
    }

    public consuming func finish(output: LogicBooleanNodeIndex, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicBooleanFunction {
        try context.checkpoint()
        guard output.rawValue >= 0, output.rawValue < operations.count else {
            throw .invalidModel("Boolean function output is not a published node")
        }
        return LogicBooleanFunction(storage: .init(inputCount: inputCount, operations: operations, output: output))
    }
}
