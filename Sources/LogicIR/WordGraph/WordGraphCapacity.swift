import LogicKernelCore

public struct WordGraphCapacity: Sendable {
    public let nodes: Int
    public let operands: Int
    public let ports: Int
    public let states: Int
    public init(nodes: Int, operands: Int, ports: Int, states: Int) throws(LogicKernelError) {
        guard nodes >= 0, operands >= 0, ports >= 0, states >= 0 else {
            throw .invalidInput("Word graph capacities must be nonnegative")
        }
        self.nodes = nodes; self.operands = operands; self.ports = ports; self.states = states
    }
    internal func storageBytes() throws(LogicKernelError) -> UInt64 {
        var result: UInt64 = 0
        for (count, stride) in [(nodes, MemoryLayout<WordLogicNode>.stride),
                                (operands, MemoryLayout<WordNodeIndex>.stride),
                                (ports, MemoryLayout<WordLogicPort>.stride),
                                (states, MemoryLayout<WordLogicState>.stride),
                                (nodes, MemoryLayout<WordNodeIndex>.stride)] {
            let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let total = result.addingReportingOverflow(bytes.partialValue)
            guard !bytes.overflow, !total.overflow else { throw .invalidInput("Word capacity byte count overflows") }
            result = total.partialValue
        }
        return result
    }
}
