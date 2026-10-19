import CircuiteFoundation
import LogicKernelCore

internal enum WordGraphValidation {
    static func validate(nodes: borrowing [WordLogicNode], operands: borrowing [WordNodeIndex],
                         ports: borrowing [WordLogicPort], states: borrowing [WordLogicState],
                         context: inout LogicKernelContext) throws(LogicKernelError) -> [WordNodeIndex] {
        let extra = states.count.multipliedReportingOverflow(by: 3)
        let edgeCount = operands.count.addingReportingOverflow(extra.partialValue)
        guard !extra.overflow, !edgeCount.overflow else { throw .invalidModel("Word validation edge count overflow") }
        var bytes: UInt64 = 0
        for (count, stride) in [(nodes.count, 2 * MemoryLayout<Int>.stride),
                                (states.count, 2 * MemoryLayout<Int>.stride),
                                (edgeCount.partialValue, 2 * MemoryLayout<Int>.stride),
                                (ports.count, MemoryLayout<DesignEntityID>.stride)] {
            let size = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let total = bytes.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !total.overflow else { throw .invalidModel("Word validation storage overflow") }
            bytes = total.partialValue
        }
        let reservation = try context.reserveStorage(byteCount: bytes)
        let result: [WordNodeIndex]
        do { result = try validateTables(nodes: nodes, operands: operands, ports: ports, states: states,
                                         edgeCapacity: edgeCount.partialValue, context: &context) }
        catch { try context.releaseStorage(reservation); throw error }
        try context.releaseStorage(reservation)
        return result
    }

    private static func validateTables(nodes: borrowing [WordLogicNode], operands: borrowing [WordNodeIndex],
                                       ports: borrowing [WordLogicPort], states: borrowing [WordLogicState],
                                       edgeCapacity: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> [WordNodeIndex] {
        var identities = Set<DesignEntityID>(); identities.reserveCapacity(nodes.count)
        var stateNodes = [Int](repeating: -1, count: states.count)
        var inputBindings = [Int](repeating: 0, count: nodes.count)
        var edges: [(Int, Int)] = []; edges.reserveCapacity(edgeCapacity)
        var expectedOperand = 0
        for index in nodes.indices {
            try context.charge(.workUnits)
            let node = nodes[index]
            guard identities.insert(node.id).inserted, node.operands.lowerBound == expectedOperand,
                  node.operands.upperBound <= operands.count else { throw .invalidModel("Invalid word identity or operand range") }
            expectedOperand = node.operands.upperBound
            for offset in node.operands {
                try context.charge(.workUnits)
                let source = operands[offset].rawValue
                try requireNode(source, count: nodes.count)
                edges.append((source, index))
            }
            switch node.operation {
            case .input:
                guard node.operands.isEmpty else { throw .invalidModel("Input word has operands") }
            case .state(let state):
                guard node.operands.isEmpty, states.indices.contains(state.rawValue), stateNodes[state.rawValue] == -1 else {
                    throw .invalidModel("Invalid or duplicate word state output")
                }
                stateNodes[state.rawValue] = index
            case .constant(let value):
                try context.charge(.workUnits, amount: UInt64(value.width.wordCount))
                guard node.operands.isEmpty, value.width == node.type.width, value.isTwoState else {
                    throw .invalidModel("Word constants require exact binary width")
                }
            case .compute(let opcode):
                try validateOpcode(opcode, node: node, nodes: nodes, operands: operands, context: &context)
            }
        }
        guard expectedOperand == operands.count else { throw .invalidModel("Unowned word operands") }
        identities.removeAll(keepingCapacity: true)
        for index in ports.indices {
            try context.charge(.workUnits)
            let port = ports[index]
            guard identities.insert(port.id).inserted else { throw .invalidModel("Duplicate word port identity") }
            try requireNode(port.value.rawValue, count: nodes.count)
            if port.direction == .input {
                guard nodes[port.value.rawValue].operation == .input, inputBindings[port.value.rawValue] == 0 else {
                    throw .invalidModel("Word input binding must be unique and primary")
                }
                inputBindings[port.value.rawValue] = 1
            }
        }
        for index in nodes.indices where nodes[index].operation == .input {
            try context.charge(.workUnits)
            guard inputBindings[index] == 1 else { throw .invalidModel("Unbound word input") }
        }
        identities.removeAll(keepingCapacity: true)
        var clock: WordNodeIndex?
        var edge: BitStateControl.Edge?
        var polarity: Bool?
        for index in states.indices {
            try context.charge(.workUnits)
            let state = states[index]
            guard identities.insert(state.id).inserted, stateNodes[index] >= 0 else { throw .invalidModel("Invalid word state identity or coverage") }
            try requireNode(state.next.rawValue, count: nodes.count)
            let type = nodes[stateNodes[index]].type
            guard nodes[state.next.rawValue].type == type else { throw .invalidModel("Next state type mismatch") }
            if let initial = state.initialValue {
                try context.charge(.workUnits, amount: UInt64(initial.width.wordCount))
                guard initial.width == type.width, initial.isTwoState else { throw .invalidModel("Initial state type mismatch or X/Z") }
            }
            let signal: WordNodeIndex
            let reset: WordReset?
            switch state.control {
            case .flipFlop(let value, let selectedEdge, let enable, let definition):
                guard polarity == nil else { throw .unsupported("Mixed latch and flip-flop word profile") }
                if let edge, edge != selectedEdge { throw .unsupported("Multiple word clock edges") }
                edge = selectedEdge; signal = value; reset = definition
                if let enable { try requireControl(enable, nodes: nodes) }
            case .latch(let value, let activeHigh, let definition):
                guard edge == nil else { throw .unsupported("Mixed flip-flop and latch word profile") }
                if let polarity, polarity != activeHigh { throw .unsupported("Multiple word latch polarities") }
                polarity = activeHigh; signal = value; reset = definition
                if let definition, definition.kind != .asynchronous { throw .unsupported("Word latch reset must be asynchronous") }
                edges.append((state.next.rawValue, stateNodes[index])); edges.append((value.rawValue, stateNodes[index]))
                if let definition { edges.append((definition.signal.rawValue, stateNodes[index])) }
            }
            try requireControl(signal, nodes: nodes)
            if let clock, clock != signal { throw .unsupported("Multiple word clocks or gates") }
            clock = signal
            if let reset {
                try context.charge(.workUnits, amount: UInt64(reset.value.width.wordCount))
                try requireControl(reset.signal, nodes: nodes)
                guard reset.value.width == type.width, reset.value.isTwoState else { throw .invalidModel("Reset value width mismatch or X/Z") }
            }
        }
        return try LogicTopology.order(nodeCount: nodes.count, edges: edges, makeIndex: WordNodeIndex.init, context: &context)
    }

    private static func validateOpcode(_ opcode: WordLogicOpcode, node: WordLogicNode,
                                        nodes: borrowing [WordLogicNode], operands: borrowing [WordNodeIndex],
                                        context: inout LogicKernelContext) throws(LogicKernelError) {
        try WordOperationValidation.validate(opcode, result: node.type, operandCount: node.operands.count,
            typeAt: { nodes[operands[node.operands.lowerBound + $0].rawValue].type }, context: &context)
    }

    private static func requireControl(_ index: WordNodeIndex, nodes: borrowing [WordLogicNode]) throws(LogicKernelError) {
        try requireNode(index.rawValue, count: nodes.count)
        guard nodes[index.rawValue].type.width.value == 1, !nodes[index.rawValue].type.isSigned else {
            throw .invalidModel("State control must be unsigned one-bit")
        }
    }
    private static func requireNode(_ index: Int, count: Int) throws(LogicKernelError) {
        guard index >= 0, index < count else { throw .invalidModel("Word node reference outside graph") }
    }
}
