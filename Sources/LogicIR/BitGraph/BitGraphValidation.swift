import CircuiteFoundation
import LogicKernelCore

internal enum BitGraphValidation {
    static func validate(nodes: borrowing [BitLogicNode], operands: borrowing [BitNodeIndex],
                         ports: borrowing [BitLogicPort], portBits: borrowing [BitNodeIndex],
                         states: borrowing [BitLogicState], context: inout LogicKernelContext)
        throws(LogicKernelError) -> [BitNodeIndex] {
        try context.checkpoint()
        let extraEdges = states.count.multipliedReportingOverflow(by: 3)
        let edgeCapacity = operands.count.addingReportingOverflow(extraEdges.partialValue)
        guard !extraEdges.overflow, !edgeCapacity.overflow, nodes.count < Int.max else {
            throw .invalidModel("Validation capacity overflow")
        }
        // Account logical workspace capacity; allocator metadata is outside managed bytes.
        var workspaceBytes: UInt64 = 0
        for (count, stride) in [(nodes.count + 1, 2 * MemoryLayout<Int>.stride),
                                (edgeCapacity.partialValue, 2 * MemoryLayout<Int>.stride),
                                (states.count, 2 * MemoryLayout<Int>.stride),
                                (nodes.count, MemoryLayout<DesignEntityID>.stride),
                                (ports.count, MemoryLayout<DesignEntityID>.stride),
                                (states.count, MemoryLayout<DesignEntityID>.stride)] {
            let size = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let total = workspaceBytes.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !total.overflow else { throw .invalidModel("Validation byte count overflow") }
            workspaceBytes = total.partialValue
        }
        let reservation = try context.reserveStorage(byteCount: workspaceBytes)
        let order: [BitNodeIndex]
        do {
            order = try validateTables(nodes: nodes, operands: operands, ports: ports, portBits: portBits,
                                           states: states, edgeCapacity: edgeCapacity.partialValue, context: &context)
        } catch {
            try context.releaseStorage(reservation)
            throw error
        }
        try context.releaseStorage(reservation)
        return order
    }

    private static func validateTables(nodes: borrowing [BitLogicNode], operands: borrowing [BitNodeIndex],
                                       ports: borrowing [BitLogicPort], portBits: borrowing [BitNodeIndex],
                                       states: borrowing [BitLogicState], edgeCapacity: Int,
                                       context: inout LogicKernelContext) throws(LogicKernelError) -> [BitNodeIndex] {
        var nodeIDs = Set<DesignEntityID>(); nodeIDs.reserveCapacity(nodes.count)
        var portIDs = Set<DesignEntityID>(); portIDs.reserveCapacity(ports.count)
        var stateIDs = Set<DesignEntityID>(); stateIDs.reserveCapacity(states.count)
        var stateNodes = [Int](repeating: -1, count: states.count)
        var inputBindings = [Int](repeating: 0, count: nodes.count)
        var edges: [(Int, Int)] = []; edges.reserveCapacity(edgeCapacity)
        var expectedOperand = 0
        for index in nodes.indices {
            try context.charge(.workUnits)
            let node = nodes[index]
            guard nodeIDs.insert(node.id).inserted else { throw .invalidModel("Duplicate node identity") }
            guard node.operands.lowerBound == expectedOperand, node.operands.upperBound <= operands.count,
                  node.operands.count == node.operation.operandCount else {
                throw .invalidModel("Invalid flat operand range")
            }
            expectedOperand = node.operands.upperBound
            for offset in node.operands {
                try context.charge(.workUnits)
                let source = operands[offset].rawValue
                try requireNode(source, count: nodes.count)
                edges.append((source, index))
            }
            if case .state(let state) = node.operation {
                guard states.indices.contains(state.rawValue), stateNodes[state.rawValue] == -1 else {
                    throw .invalidModel("State output is missing, duplicated or out of range")
                }
                stateNodes[state.rawValue] = index
            }
        }
        guard expectedOperand == operands.count else { throw .invalidModel("Unowned operands") }
        var expectedBinding = 0
        for portIndex in ports.indices {
            let port = ports[portIndex]
            try context.charge(.workUnits)
            guard portIDs.insert(port.id).inserted, !port.bits.isEmpty,
                  port.bits.lowerBound == expectedBinding, port.bits.upperBound <= portBits.count else {
                throw .invalidModel("Invalid port identity or binding range")
            }
            expectedBinding = port.bits.upperBound
            for offset in port.bits {
                try context.charge(.workUnits)
                let node = portBits[offset].rawValue
                try requireNode(node, count: nodes.count)
                if port.direction == .input {
                    guard nodes[node].operation == .input, inputBindings[node] == 0 else {
                        throw .invalidModel("Input port must bind a unique primary input")
                    }
                    inputBindings[node] = 1
                }
            }
        }
        guard expectedBinding == portBits.count else { throw .invalidModel("Unowned port bits") }
        for index in nodes.indices where nodes[index].operation == .input {
            try context.charge(.workUnits)
            guard inputBindings[index] == 1 else { throw .invalidModel("Primary input has no port binding") }
        }
        var sharedControl: BitNodeIndex?
        var sharedEdge: BitStateControl.Edge?
        var sharedPolarity: Bool?
        for index in states.indices {
            try context.charge(.workUnits)
            let state = states[index]
            guard stateIDs.insert(state.id).inserted, stateNodes[index] >= 0 else {
                throw .invalidModel("Duplicate state identity or missing state output")
            }
            try requireNode(state.next.rawValue, count: nodes.count)
            let signal: BitNodeIndex
            let reset: BitReset?
            switch state.control {
            case .flipFlop(let clock, let edge, let enable, let definition):
                guard sharedPolarity == nil else { throw .unsupported("Mixed flip-flop and latch profile") }
                if let previous = sharedEdge, previous != edge { throw .unsupported("Multiple clock edges") }
                sharedEdge = edge
                signal = clock; reset = definition
                if let enable { try requireNode(enable.rawValue, count: nodes.count) }
            case .latch(let gate, let activeHigh, let definition):
                guard sharedEdge == nil else { throw .unsupported("Mixed latch and flip-flop profile") }
                if let previous = sharedPolarity, previous != activeHigh { throw .unsupported("Multiple latch polarities") }
                sharedPolarity = activeHigh
                signal = gate; reset = definition
                if let definition, definition.kind != .asynchronous {
                    throw .unsupported("Latch reset must be asynchronous")
                }
                edges.append((state.next.rawValue, stateNodes[index]))
                edges.append((gate.rawValue, stateNodes[index]))
                if let definition { edges.append((definition.signal.rawValue, stateNodes[index])) }
            }
            try requireNode(signal.rawValue, count: nodes.count)
            if let previous = sharedControl, previous != signal { throw .unsupported("Multiple clock or gate inputs") }
            sharedControl = signal
            if let reset { try requireNode(reset.signal.rawValue, count: nodes.count) }
        }
        return try LogicTopology.order(nodeCount: nodes.count, edges: edges,
                                       makeIndex: BitNodeIndex.init, context: &context)
    }

    private static func requireNode(_ index: Int, count: Int) throws(LogicKernelError) {
        guard index >= 0 && index < count else { throw .invalidModel("Node reference outside graph") }
    }
}
