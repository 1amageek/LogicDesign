import CircuiteFoundation
import LogicKernelCore

public struct MappedGateBuilder: ~Copyable {
    private let library: LogicTechnologyLibrary
    private let capacity: MappedGraphCapacity
    private var nets: [MappedGateNet] = []
    private var instances: [MappedGateInstance] = []
    private var pins: [MappedNetIndex] = []
    private var ports: [MappedGatePort] = []
    private var bits: [MappedNetIndex] = []

    public init(library: LogicTechnologyLibrary, capacity: MappedGraphCapacity, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        try context.checkpoint()
        let nodes = UInt64(capacity.nets).addingReportingOverflow(UInt64(capacity.instances))
        let edges = UInt64(capacity.pinConnections).addingReportingOverflow(UInt64(capacity.portBits))
        guard !nodes.overflow, !edges.overflow else { throw .invalidInput("Mapped resource capacity overflows") }
        try context.require(.nodes, amount: nodes.partialValue)
        try context.require(.edges, amount: edges.partialValue)
        _ = try context.reserveStorage(byteCount: capacity.storageBytes())
        self.library = library; self.capacity = capacity
        nets.reserveCapacity(capacity.nets); instances.reserveCapacity(capacity.instances)
        pins.reserveCapacity(capacity.pinConnections); ports.reserveCapacity(capacity.ports); bits.reserveCapacity(capacity.portBits)
    }

    public mutating func addNet(_ net: MappedGateNet, context: inout LogicKernelContext)
        throws(LogicKernelError) -> MappedNetIndex {
        guard nets.count < capacity.nets else { throw .invalidInput("Mapped net capacity exhausted") }
        try context.observeBitWidth(1)
        try context.charge(.nodes)
        let index = MappedNetIndex(nets.count)
        nets.append(net)
        return index
    }

    public mutating func addInstance(id: DesignEntityID, cell: LogicCellIndex, pinNets: borrowing [MappedNetIndex],
                                     stateID: DesignEntityID? = nil, initialValue: Bool? = nil,
                                     origin: LogicKernelSourceRange? = nil, context: inout LogicKernelContext)
        throws(LogicKernelError) -> MappedInstanceIndex {
        guard instances.count < capacity.instances, pinNets.count <= capacity.pinConnections - pins.count else {
            throw .invalidInput("Mapped instance or connection capacity exhausted")
        }
        let definition = try library.cell(at: cell)
        guard pinNets.count == definition.pinCount, (stateID != nil) == (definition.state != nil),
              stateID != nil || initialValue == nil else { throw .invalidModel("Mapped cell pins or state binding do not match") }
        try context.charge(.workUnits, amount: UInt64(pinNets.count) + 1)
        try context.charge(.nodes)
        try context.charge(.edges, amount: UInt64(pinNets.count))
        if stateID != nil { try context.charge(.states) }
        let index = MappedInstanceIndex(instances.count)
        let start = pins.count
        for index in pinNets.indices { pins.append(pinNets[index]) }
        instances.append(.init(id: id, cell: cell, pins: start..<pins.count, stateID: stateID,
                               initialValue: initialValue, origin: origin))
        return index
    }

    public mutating func addPort(id: DesignEntityID, direction: MappedGatePort.Direction, nets: borrowing [MappedNetIndex],
                                 context: inout LogicKernelContext) throws(LogicKernelError) {
        guard ports.count < capacity.ports, nets.count <= capacity.portBits - bits.count else {
            throw .invalidInput("Mapped port capacity exhausted")
        }
        guard !nets.isEmpty else { throw .invalidModel("Mapped port width must be positive") }
        try context.observeBitWidth(UInt64(nets.count))
        try context.charge(.workUnits, amount: UInt64(nets.count) + 1)
        try context.charge(.edges, amount: UInt64(nets.count))
        let start = bits.count
        for index in nets.indices { bits.append(nets[index]) }
        ports.append(.init(id: id, direction: direction, bits: start..<bits.count))
    }

    @available(macOS 26.0, *)
    public consuming func finish(context: inout LogicKernelContext) throws(LogicKernelError) -> MappedGateDesign {
        let result = try MappedGraphValidation.validate(library: library, nets: nets, instances: instances,
                                                       pins: pins, ports: ports, bits: bits, context: &context)
        return MappedGateDesign(storage: .init(library: library, nets: nets, instances: instances, pins: pins,
                                               ports: ports, bits: bits, order: result.order, clocks: result.clocks, stateCount: result.states))
    }
}
