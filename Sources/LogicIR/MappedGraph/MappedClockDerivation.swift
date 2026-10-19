import LogicKernelCore

internal enum MappedClockDerivation {
    struct Trace {
        let root: MappedNetIndex
        let inverted: Bool
    }

    @available(macOS 26.0, *)
    static func derive(library: borrowing LogicTechnologyLibrary, nets: borrowing [MappedGateNet],
                       instances: borrowing [MappedGateInstance], pins: borrowing [MappedNetIndex],
                       order: borrowing [MappedEvaluationStep], functionCapacity: Int,
                       reachable: inout [Bool], context: inout LogicKernelContext)
        throws(LogicKernelError) -> [MappedStateClock] {
        var traces = [Trace?](repeating: nil, count: nets.count)
        var values = [UInt8](repeating: 0, count: functionCapacity)
        for offset in order.indices {
            let step = order[offset]
            try context.charge(.workUnits)
            guard case .net(let net) = step else { continue }
            switch nets[net.rawValue].driver {
            case .input: traces[net.rawValue] = .init(root: net, inverted: false)
            case .constant: break
            case .instanceOutput(let index, let pin):
                let instance = instances[index.rawValue]
                let cell = try library.cell(at: instance.cell)
                guard cell.state == nil, let function = try cell.pin(at: pin).function,
                      let unary = try unary(function, reachable: &reachable, values: &values, context: &context),
                      let source = traces[pins[instance.pins.lowerBound + unary.slot].rawValue] else { continue }
                traces[net.rawValue] = .init(root: source.root, inverted: source.inverted != unary.inverted)
            }
        }
        var clocks: [MappedStateClock] = []
        clocks.reserveCapacity(instances.count)
        for index in instances.indices {
            try context.charge(.workUnits)
            let instance = instances[index]
            guard let state = try library.cell(at: instance.cell).state,
                  case .flipFlop(let pin, let rising) = state.control else { continue }
            let carrier = pins[instance.pins.lowerBound + pin.rawValue]
            let lineage: MappedClockLineage
            if let trace = traces[carrier.rawValue] {
                lineage = .primaryInput(root: trace.root, inverted: trace.inverted, risingEdge: rising != trace.inverted)
            } else { lineage = .opaque(carrier: carrier, risingEdge: rising) }
            let clock = MappedStateClock(instance: .init(index), carrier: carrier, risingEdge: rising, lineage: lineage)
            if let first = clocks.first, first.carrier != carrier || first.risingEdge != rising {
                guard case .primaryInput(let root, _, let edge) = first.lineage,
                      case .primaryInput(let otherRoot, _, let otherEdge) = lineage,
                      root == otherRoot, edge == otherEdge else {
                    throw .unsupported("Multiple mapped logical clocks or effective edges")
                }
            }
            clocks.append(clock)
        }
        return clocks
    }

    @available(macOS 26.0, *)
    private static func unary(_ function: borrowing LogicBooleanFunction, reachable: inout [Bool],
                              values: inout [UInt8], context: inout LogicKernelContext)
        throws(LogicKernelError) -> (slot: Int, inverted: Bool)? {
        for index in 0..<function.nodeCount { try context.charge(.workUnits); reachable[index] = false }
        reachable[function.output.rawValue] = true
        return try function.withOperations { operations throws(LogicKernelError) in
            var slot: Int?
            var index = operations.count
            while index > 0 {
                index -= 1
                try context.charge(.workUnits)
                guard reachable[index] else { continue }
                switch operations[index] {
                case .constant: break
                case .input(let input):
                    if let previous = slot, previous != input { return nil }
                    slot = input
                case .invert(let a): reachable[a.rawValue] = true
                case .and(let a, let b), .or(let a, let b), .xor(let a, let b):
                    reachable[a.rawValue] = true; reachable[b.rawValue] = true
                }
            }
            guard let slot else { return nil }
            // Two packed truth assignments establish identity or inversion for the sole reachable input.
            for index in operations.indices {
                try context.charge(.workUnits)
                guard reachable[index] else { continue }
                switch operations[index] {
                case .constant(let value): values[index] = value ? 3 : 0
                case .input: values[index] = 2
                case .invert(let a): values[index] = values[a.rawValue] ^ 3
                case .and(let a, let b): values[index] = values[a.rawValue] & values[b.rawValue]
                case .or(let a, let b): values[index] = values[a.rawValue] | values[b.rawValue]
                case .xor(let a, let b): values[index] = values[a.rawValue] ^ values[b.rawValue]
                }
            }
            switch values[function.output.rawValue] {
            case 2: return (slot, false)
            case 1: return (slot, true)
            default: return nil
            }
        }
    }
}
