import CircuiteFoundation
import LogicKernelCore

internal enum MappedGraphValidation {
    @available(macOS 26.0, *)
    static func validate(library: borrowing LogicTechnologyLibrary, nets: borrowing [MappedGateNet],
                         instances: borrowing [MappedGateInstance], pins: borrowing [MappedNetIndex],
                         ports: borrowing [MappedGatePort], bits: borrowing [MappedNetIndex],
                         context: inout LogicKernelContext) throws(LogicKernelError) -> (order: [MappedEvaluationStep], clocks: [MappedStateClock], states: Int) {
        try context.checkpoint()
        let measured = try measure(library: library, instances: instances, context: &context)
        var identities = 0
        for count in [nets.count, instances.count, ports.count, instances.count] {
            let sum = identities.addingReportingOverflow(count)
            guard !sum.overflow else { throw .invalidModel("Mapped identity workspace overflows") }
            identities = sum.partialValue
        }
        var bytes: UInt64 = 0
        for (count, stride) in [(identities, MemoryLayout<DesignEntityID>.stride),
                                (nets.count, MemoryLayout<Int>.stride),
                                (instances.count, 2 * MemoryLayout<Int>.stride),
                                (measured.edges, 2 * MemoryLayout<Int>.stride),
                                (measured.functionNodes, MemoryLayout<Bool>.stride + MemoryLayout<UInt8>.stride),
                                (nets.count, MemoryLayout<MappedClockDerivation.Trace?>.stride)] {
            let size = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let sum = bytes.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !sum.overflow else { throw .invalidModel("Mapped validation storage overflows") }
            bytes = sum.partialValue
        }
        try context.require(.edges, amount: UInt64(measured.edges))
        let receipt = try context.reserveStorage(byteCount: bytes)
        let result: (order: [MappedEvaluationStep], clocks: [MappedStateClock], states: Int)
        do {
            result = try validateTables(library: library, nets: nets, instances: instances, pins: pins,
                ports: ports, bits: bits, identityCapacity: identities, edgeCapacity: measured.edges,
                functionCapacity: measured.functionNodes, context: &context)
        } catch { try context.releaseStorage(receipt); throw error }
        try context.releaseStorage(receipt)
        return result
    }

    @available(macOS 26.0, *)
    private static func measure(library: borrowing LogicTechnologyLibrary, instances: borrowing [MappedGateInstance],
                                context: inout LogicKernelContext) throws(LogicKernelError) -> (edges: Int, functionNodes: Int) {
        var edgeCount = 0
        var maximum = 0
        func admit(_ count: Int) throws(LogicKernelError) {
            let sum = edgeCount.addingReportingOverflow(count)
            guard !sum.overflow else { throw .invalidModel("Mapped dependency capacity overflows") }
            edgeCount = sum.partialValue
            maximum = max(maximum, count)
        }
        for index in instances.indices {
            try context.charge(.workUnits)
            let instance = instances[index]
            let cell = try library.cell(at: instance.cell)
            try cell.withPins { pins throws(LogicKernelError) in
                for index in pins.indices {
                    try context.charge(.workUnits)
                    if let function = pins[index].function { try admit(function.nodeCount) }
                }
            }
            if let state = cell.state, case .latch = state.control {
                try admit(state.nextState.nodeCount)
                try admit(2)
            }
        }
        return (edgeCount, maximum)
    }

    @available(macOS 26.0, *)
    private static func validateTables(library: borrowing LogicTechnologyLibrary, nets: borrowing [MappedGateNet],
                                       instances: borrowing [MappedGateInstance], pins: borrowing [MappedNetIndex],
                                       ports: borrowing [MappedGatePort], bits: borrowing [MappedNetIndex],
                                       identityCapacity: Int, edgeCapacity: Int, functionCapacity: Int,
                                       context: inout LogicKernelContext)
        throws(LogicKernelError) -> (order: [MappedEvaluationStep], clocks: [MappedStateClock], states: Int) {
        var identifiers = Set<DesignEntityID>(); identifiers.reserveCapacity(identityCapacity)
        var inputBindings = [Int](repeating: 0, count: nets.count)
        var stateVertices = [Int](repeating: -1, count: instances.count)
        var stateInstances: [MappedInstanceIndex] = []; stateInstances.reserveCapacity(instances.count)
        var edges: [(Int, Int)] = []; edges.reserveCapacity(edgeCapacity)
        var reachable = [Bool](repeating: false, count: functionCapacity)
        for index in nets.indices {
            try context.charge(.workUnits)
            let net = nets[index]
            guard identifiers.insert(net.id).inserted else { throw .invalidModel("Duplicate mapped net identity") }
        }
        var expectedPin = 0
        var sharedControl: MappedNetIndex?
        var sharedKind: Bool?
        var sharedPolarity: Bool?
        for index in instances.indices {
            try context.charge(.workUnits)
            let instance = instances[index]
            let cell = try library.cell(at: instance.cell)
            guard identifiers.insert(instance.id).inserted,
                  instance.pins.lowerBound == expectedPin, instance.pins.upperBound <= pins.count,
                  instance.pins.count == cell.pinCount else { throw .invalidModel("Invalid mapped instance identity or pin range") }
            expectedPin = instance.pins.upperBound
            guard (instance.stateID != nil) == (cell.state != nil), instance.stateID != nil || instance.initialValue == nil else {
                throw .invalidModel("Mapped instance state does not match its cell")
            }
            for offset in instance.pins {
                try context.charge(.workUnits)
                try requireNet(pins[offset], count: nets.count)
            }
            try cell.withPins { definitions throws(LogicKernelError) in
                for pin in definitions.indices {
                    try context.charge(.workUnits)
                    if definitions[pin].direction == .output {
                        let net = pins[instance.pins.lowerBound + pin].rawValue
                        guard nets[net].driver == .instanceOutput(.init(index), .init(pin)) else {
                            throw .invalidModel("Output pin connection does not match the net driver")
                        }
                    }
                }
            }
            if let state = cell.state, let stateID = instance.stateID {
                guard identifiers.insert(stateID).inserted else { throw .invalidModel("Duplicate mapped state identity") }
                let vertex = nets.count.addingReportingOverflow(stateInstances.count)
                guard !vertex.overflow else { throw .invalidModel("Mapped state vertex overflows") }
                stateVertices[index] = vertex.partialValue; stateInstances.append(.init(index))
                let controlNet = pins[instance.pins.lowerBound + state.control.pin.rawValue]
                let isFF: Bool
                let polarity: Bool
                switch state.control {
                case .flipFlop(_, let rising): isFF = true; polarity = rising
                case .latch(_, let activeHigh): isFF = false; polarity = activeHigh
                }
                if !isFF, let previous = sharedControl, previous != controlNet { throw .unsupported("Multiple mapped clocks or gates") }
                if let previous = sharedKind, previous != isFF { throw .unsupported("Mixed mapped FF and latch profile") }
                if !isFF, let previous = sharedPolarity, previous != polarity { throw .unsupported("Multiple mapped edges or gate polarities") }
                sharedControl = controlNet; sharedKind = isFF; sharedPolarity = polarity
            }
        }
        guard expectedPin == pins.count else { throw .invalidModel("Unowned mapped pin connections") }
        for index in nets.indices {
            try context.charge(.workUnits)
            if case .instanceOutput(let instanceIndex, let pinIndex) = nets[index].driver {
                guard instances.indices.contains(instanceIndex.rawValue) else { throw .invalidModel("Mapped driver instance is out of range") }
                let instance = instances[instanceIndex.rawValue]
                let cell = try library.cell(at: instance.cell)
                guard pinIndex.rawValue >= 0, pinIndex.rawValue < cell.pinCount,
                      try cell.pin(at: pinIndex).direction == .output,
                      pins[instance.pins.lowerBound + pinIndex.rawValue].rawValue == index else {
                    throw .invalidModel("Mapped driver is not the connected physical output")
                }
            }
        }
        var expectedBit = 0
        for index in ports.indices {
            try context.charge(.workUnits)
            let port = ports[index]
            guard identifiers.insert(port.id).inserted, !port.bits.isEmpty,
                  port.bits.lowerBound == expectedBit, port.bits.upperBound <= bits.count else {
                throw .invalidModel("Invalid mapped port identity or bit range")
            }
            expectedBit = port.bits.upperBound
            for offset in port.bits {
                try context.charge(.workUnits)
                let net = bits[offset]
                try requireNet(net, count: nets.count)
                if port.direction == .input {
                    guard nets[net.rawValue].driver == .input, inputBindings[net.rawValue] == 0 else {
                        throw .invalidModel("Mapped input port must bind a unique primary input")
                    }
                    inputBindings[net.rawValue] = 1
                }
            }
        }
        guard expectedBit == bits.count else { throw .invalidModel("Unowned mapped port bits") }
        for index in nets.indices where nets[index].driver == .input {
            try context.charge(.workUnits)
            guard inputBindings[index] == 1 else { throw .invalidModel("Mapped primary input has no port") }
        }
        for index in instances.indices {
            try context.charge(.workUnits)
            let instance = instances[index]
            let cell = try library.cell(at: instance.cell)
            try cell.withPins { definitions throws(LogicKernelError) in
                for pin in definitions.indices {
                    try context.charge(.workUnits)
                    if let function = definitions[pin].function {
                        try connect(function, instance: instance, pinCount: cell.pinCount, stateVertex: stateVertices[index],
                                    destination: pins[instance.pins.lowerBound + pin].rawValue, pins: pins,
                                    reachable: &reachable, edges: &edges, context: &context)
                    }
                }
            }
            if let state = cell.state, case .latch = state.control {
                let destination = stateVertices[index]
                try connect(state.nextState, instance: instance, pinCount: cell.pinCount, stateVertex: destination,
                            destination: destination, pins: pins, reachable: &reachable, edges: &edges, context: &context)
                try context.charge(.edges)
                edges.append((pins[instance.pins.lowerBound + state.control.pin.rawValue].rawValue, destination))
                if let reset = state.asynchronousReset {
                    try context.charge(.edges)
                    edges.append((pins[instance.pins.lowerBound + reset.pin.rawValue].rawValue, destination))
                }
            }
        }
        let vertices = nets.count.addingReportingOverflow(stateInstances.count)
        guard !vertices.overflow else { throw .invalidModel("Mapped topology size overflows") }
        let order = try LogicTopology.order(nodeCount: vertices.partialValue, edges: edges, makeIndex: { vertex in
            vertex < nets.count ? MappedEvaluationStep.net(.init(vertex)) : .state(stateInstances[vertex - nets.count])
        }, context: &context)
        let clocks = try MappedClockDerivation.derive(library: library, nets: nets, instances: instances,
            pins: pins, order: order, functionCapacity: functionCapacity, reachable: &reachable, context: &context)
        return (order, clocks, stateInstances.count)
    }

    @available(macOS 26.0, *)
    private static func connect(_ function: borrowing LogicBooleanFunction, instance: MappedGateInstance, pinCount: Int,
                                stateVertex: Int, destination: Int, pins: borrowing [MappedNetIndex],
                                reachable: inout [Bool], edges: inout [(Int, Int)], context: inout LogicKernelContext)
        throws(LogicKernelError) {
        for index in 0..<function.nodeCount { try context.charge(.workUnits); reachable[index] = false }
        reachable[function.output.rawValue] = true
        try function.withOperations { operations throws(LogicKernelError) in
            var index = operations.count
            while index > 0 {
                index -= 1
                try context.charge(.workUnits)
                guard reachable[index] else { continue }
                switch operations[index] {
                case .constant: break
                case .input(let slot):
                    let source = slot < pinCount ? pins[instance.pins.lowerBound + slot].rawValue : stateVertex
                    guard source >= 0 else { throw .invalidModel("Cell function has no mapped state vertex") }
                    try context.charge(.edges)
                    edges.append((source, destination))
                case .invert(let a): reachable[a.rawValue] = true
                case .and(let a, let b), .or(let a, let b), .xor(let a, let b):
                    reachable[a.rawValue] = true; reachable[b.rawValue] = true
                }
            }
        }
    }

    private static func requireNet(_ index: MappedNetIndex, count: Int) throws(LogicKernelError) {
        guard index.rawValue >= 0, index.rawValue < count else { throw .invalidModel("Mapped net reference is out of range") }
    }
}
