import CircuiteFoundation
import LogicKernelCore

public struct WordLogicBuilder: ~Copyable {
    private let capacity: WordGraphCapacity
    private var nodes: [WordLogicNode] = []
    private var operands: [WordNodeIndex] = []
    private var ports: [WordLogicPort] = []
    private var states: [WordLogicState] = []
    public init(capacity: WordGraphCapacity, context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.require(.nodes, amount: UInt64(capacity.nodes))
        try context.require(.edges, amount: UInt64(capacity.operands))
        try context.require(.states, amount: UInt64(capacity.states))
        _ = try context.reserveStorage(byteCount: capacity.storageBytes())
        self.capacity = capacity
        nodes.reserveCapacity(capacity.nodes); operands.reserveCapacity(capacity.operands)
        ports.reserveCapacity(capacity.ports); states.reserveCapacity(capacity.states)
    }
    public mutating func addNode(id: DesignEntityID, type: WordLogicType, operation: WordLogicOperation,
                                 inputs: borrowing [WordNodeIndex] = [], origin: LogicKernelSourceRange? = nil,
                                 context: inout LogicKernelContext) throws(LogicKernelError) -> WordNodeIndex {
        guard nodes.count < capacity.nodes, inputs.count <= capacity.operands - operands.count else {
            throw .invalidInput("Word node or operand builder capacity exhausted")
        }
        let arity: Int?
        switch operation {
        case .input, .state, .constant: arity = 0
        case .compute(let opcode): arity = opcode.fixedOperandCount
        }
        guard arity == nil ? !inputs.isEmpty : inputs.count == arity else { throw .invalidModel("Word opcode arity mismatch") }
        try context.observeBitWidth(UInt64(type.width.value))
        try context.charge(.nodes)
        try context.charge(.edges, amount: UInt64(inputs.count))
        let index = WordNodeIndex(nodes.count); let start = operands.count
        for offset in inputs.indices { operands.append(inputs[offset]) }
        nodes.append(WordLogicNode(id: id, type: type, operation: operation,
                                  operands: start..<operands.count, origin: origin))
        return index
    }
    public mutating func addPort(_ port: WordLogicPort, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard ports.count < capacity.ports else { throw .invalidInput("Word port builder capacity exhausted") }
        try context.charge(.edges)
        ports.append(port)
    }
    public mutating func addState(_ state: WordLogicState, context: inout LogicKernelContext)
        throws(LogicKernelError) -> WordStateIndex {
        guard states.count < capacity.states else { throw .invalidInput("Word state builder capacity exhausted") }
        try context.charge(.states)
        let controlEdges: UInt64
        switch state.control {
        case .flipFlop(_, _, let enable, let reset): controlEdges = 2 + (enable == nil ? 0 : 1) + (reset == nil ? 0 : 1)
        case .latch(_, _, let reset): controlEdges = 2 + (reset == nil ? 0 : 1)
        }
        try context.charge(.edges, amount: controlEdges)
        let index = WordStateIndex(states.count); states.append(state); return index
    }
    public consuming func finish(context: inout LogicKernelContext) throws(LogicKernelError) -> WordLogicDesign {
        let order = try WordGraphValidation.validate(nodes: nodes, operands: operands, ports: ports,
                                                     states: states, context: &context)
        return WordLogicDesign(storage: WordLogicDesign.Storage(nodes: nodes, operands: operands,
                                                               ports: ports, states: states, order: order))
    }
}
