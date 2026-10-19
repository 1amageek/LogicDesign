import LogicKernelCore

public struct BitGraphCapacity: Sendable {
    public let nodes: Int
    public let operands: Int
    public let ports: Int
    public let portBits: Int
    public let states: Int

    public init(nodes: Int, operands: Int, ports: Int, portBits: Int, states: Int) throws(LogicKernelError) {
        guard nodes >= 0, operands >= 0, ports >= 0, portBits >= 0, states >= 0 else {
            throw .invalidInput("Graph capacities must be nonnegative")
        }
        self.nodes = nodes; self.operands = operands; self.ports = ports
        self.portBits = portBits; self.states = states
    }

    internal func storageBytes() throws(LogicKernelError) -> UInt64 {
        var result: UInt64 = 0
        for (count, stride) in [(nodes, MemoryLayout<BitLogicNode>.stride),
                                (operands, MemoryLayout<BitNodeIndex>.stride),
                                (ports, MemoryLayout<BitLogicPort>.stride),
                                (portBits, MemoryLayout<BitNodeIndex>.stride),
                                (states, MemoryLayout<BitLogicState>.stride),
                                (nodes, MemoryLayout<BitNodeIndex>.stride)] {
            let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let total = result.addingReportingOverflow(bytes.partialValue)
            guard !bytes.overflow && !total.overflow else {
                throw .invalidInput("Graph capacity byte count overflows")
            }
            result = total.partialValue
        }
        return result
    }
}
