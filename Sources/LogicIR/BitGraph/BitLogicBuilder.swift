import CircuiteFoundation
import LogicKernelCore

public struct BitLogicBuilder: ~Copyable {
    private let capacity: BitGraphCapacity
    private var nodes: [BitLogicNode] = []
    private var operands: [BitNodeIndex] = []
    private var ports: [BitLogicPort] = []
    private var portBits: [BitNodeIndex] = []
    private var states: [BitLogicState] = []

    public init(capacity: BitGraphCapacity, context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.require(.nodes, amount: UInt64(capacity.nodes))
        try context.require(.edges, amount: UInt64(capacity.operands))
        try context.require(.states, amount: UInt64(capacity.states))
        _ = try context.reserveStorage(byteCount: capacity.storageBytes())
        self.capacity = capacity
        nodes.reserveCapacity(capacity.nodes); operands.reserveCapacity(capacity.operands)
        ports.reserveCapacity(capacity.ports); portBits.reserveCapacity(capacity.portBits)
        states.reserveCapacity(capacity.states)
    }

    public mutating func addNode(id: DesignEntityID, operation: BitOperation,
                                 inputs: borrowing [BitNodeIndex] = [], origin: LogicKernelSourceRange? = nil,
                                 context: inout LogicKernelContext) throws(LogicKernelError) -> BitNodeIndex {
        guard nodes.count < capacity.nodes, inputs.count <= capacity.operands - operands.count else {
            throw .invalidInput("Node or operand builder capacity exhausted")
        }
        guard inputs.count == operation.operandCount else { throw .invalidModel("Opcode arity mismatch") }
        try context.observeBitWidth(1)
        try context.charge(.nodes)
        try context.charge(.edges, amount: UInt64(inputs.count))
        let result = BitNodeIndex(nodes.count)
        let start = operands.count
        for index in inputs.indices { operands.append(inputs[index]) }
        nodes.append(BitLogicNode(id: id, operation: operation, operands: start..<operands.count, origin: origin))
        return result
    }

    public mutating func addPort(id: DesignEntityID, direction: BitLogicPort.Direction,
                                 bits: borrowing [BitNodeIndex], context: inout LogicKernelContext)
        throws(LogicKernelError) {
        guard ports.count < capacity.ports, bits.count <= capacity.portBits - portBits.count else {
            throw .invalidInput("Port builder capacity exhausted")
        }
        guard !bits.isEmpty else { throw .invalidModel("Ports require at least one bit") }
        try context.observeBitWidth(UInt64(bits.count))
        try context.charge(.edges, amount: UInt64(bits.count))
        let start = portBits.count
        for index in bits.indices { portBits.append(bits[index]) }
        ports.append(BitLogicPort(id: id, direction: direction, bits: start..<portBits.count))
    }

    public mutating func addState(_ state: BitLogicState, context: inout LogicKernelContext)
        throws(LogicKernelError) -> BitStateIndex {
        guard states.count < capacity.states else { throw .invalidInput("State builder capacity exhausted") }
        try context.charge(.states)
        let controlEdges: UInt64
        switch state.control {
        case .flipFlop(_, _, let enable, let reset):
            controlEdges = 2 + (enable == nil ? 0 : 1) + (reset == nil ? 0 : 1)
        case .latch(_, _, let reset):
            controlEdges = 2 + (reset == nil ? 0 : 1)
        }
        try context.charge(.edges, amount: controlEdges)
        let index = BitStateIndex(states.count)
        states.append(state)
        return index
    }

    public consuming func finish(context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        let order = try BitGraphValidation.validate(nodes: nodes, operands: operands, ports: ports,
                                                    portBits: portBits, states: states, context: &context)
        return BitLogicDesign(storage: BitLogicDesign.Storage(nodes: nodes, operands: operands,
                         ports: ports, portBits: portBits, states: states, order: order))
    }
}
