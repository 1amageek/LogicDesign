import LogicKernelCore

public struct MappedGraphCapacity: Sendable {
    public let nets: Int
    public let instances: Int
    public let pinConnections: Int
    public let ports: Int
    public let portBits: Int

    public init(nets: Int, instances: Int, pinConnections: Int, ports: Int, portBits: Int) throws(LogicKernelError) {
        guard nets >= 0, instances >= 0, pinConnections >= 0, ports >= 0, portBits >= 0 else {
            throw .invalidInput("Mapped graph capacities must be nonnegative")
        }
        self.nets = nets; self.instances = instances; self.pinConnections = pinConnections
        self.ports = ports; self.portBits = portBits
    }

    internal func storageBytes() throws(LogicKernelError) -> UInt64 {
        let vertices = nets.addingReportingOverflow(instances)
        guard !vertices.overflow else { throw .invalidInput("Mapped vertex capacity overflows") }
        var total: UInt64 = UInt64(MemoryLayout<(LogicTechnologyLibrary, [MappedGateNet], [MappedGateInstance],
            [MappedNetIndex], [MappedGatePort], [MappedNetIndex], [MappedEvaluationStep], [MappedStateClock], Int)>.stride)
        for (count, stride) in [(nets, MemoryLayout<MappedGateNet>.stride),
                                (instances, MemoryLayout<MappedGateInstance>.stride),
                                (instances, MemoryLayout<MappedStateClock>.stride),
                                (pinConnections, MemoryLayout<MappedNetIndex>.stride),
                                (ports, MemoryLayout<MappedGatePort>.stride),
                                (portBits, MemoryLayout<MappedNetIndex>.stride),
                                (vertices.partialValue, MemoryLayout<MappedEvaluationStep>.stride)] {
            let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let sum = total.addingReportingOverflow(bytes.partialValue)
            guard !bytes.overflow, !sum.overflow else { throw .invalidInput("Mapped storage capacity overflows") }
            total = sum.partialValue
        }
        return total
    }
}
