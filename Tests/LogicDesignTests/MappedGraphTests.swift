import Testing
import Foundation
import LogicDesignSerialization
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicKernelProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct MappedGraphTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private enum Kind { case buffer, inverter, nand, ff(Bool), latch(Bool) }
    private func context(storage: UInt64 = 10_000_000, control: any LogicRunControlling = Control()) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        limits[.managedStorageBytes] = storage
        return .init(limits: try .init(maximums: limits), control: control)
    }
    private func id(_ value: Int) throws -> DesignEntityID { try .init(rawValue: UInt64(value)) }
    private func source(_ digit: String = "12") throws -> ArtifactID {
        try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: digit, count: 32)), byteCount: 1000)
    }
    @available(macOS 26.0, *)
    private func reject(_ builder: consuming MappedGateBuilder, expected: Int = 0, context: inout LogicKernelContext) {
        do throws(LogicKernelError) {
            _ = try builder.finish(context: &context)
            Issue.record("Invalid mapped design was published")
        } catch {
            switch error {
            case .invalidModel: #expect(expected == 0)
            case .unsupported: #expect(expected == 1)
            case .cancelled: #expect(expected == 2)
            default: Issue.record("Mapped refusal used an unexpected failure category: \(error)")
            }
        }
    }
    @available(macOS 26.0, *)
    private func library(_ kinds: [Kind], sourceDigit: String = "12", area: Double = 1,
                         context: inout LogicKernelContext) throws -> LogicTechnologyLibrary {
        var library = try LogicTechnologyLibraryBuilder(cellCapacity: kinds.count, totalPinCapacity: kinds.count * 4, context: &context)
        for (index, kind) in kinds.enumerated() {
            let sequential: Bool
            switch kind { case .ff, .latch: sequential = true; default: sequential = false }
            let count = sequential ? 4 : 3
            let slots = count + (sequential ? 1 : 0)
            var function = try LogicBooleanFunctionBuilder(inputCount: slots, nodeCapacity: 4, context: &context)
            let a = try function.append(.input(sequential ? count : 0), context: &context)
            let b = try function.append(.input(1), context: &context)
            let output: LogicBooleanNodeIndex
            switch kind {
            case .inverter: output = try function.append(.invert(a), context: &context)
            case .nand:
                let and = try function.append(.and(a, b), context: &context)
                output = try function.append(.invert(and), context: &context)
            default: output = a
            }
            let f = try function.finish(output: output, context: &context)
            let base = 1000 + index * 10
            var cell = try LogicTechnologyCellBuilder(id: id(base), name: "C\(index)", pinCapacity: count, context: &context)
            for pin in 0..<(count - 1) {
                _ = try cell.append(.init(id: id(base + pin + 1), name: "I\(pin)", direction: .input), context: &context)
            }
            _ = try cell.append(.init(id: id(base + count), name: "Y", direction: .output, function: f), context: &context)
            let state: LogicCellStateDefinition?
            if sequential {
                var data = try LogicBooleanFunctionBuilder(inputCount: slots, nodeCapacity: 1, context: &context)
                let d = try data.append(.input(0), context: &context)
                let next = try data.finish(output: d, context: &context)
                let control: LogicCellStateDefinition.Control
                switch kind {
                case .ff(let positive): control = .flipFlop(clock: .init(1), risingEdge: positive)
                case .latch(let positive): control = .latch(gate: .init(1), activeHigh: positive)
                default: throw LogicKernelError.invalidModel("Invalid test sequential kind")
                }
                state = .init(control: control, nextState: next, asynchronousReset: .init(pin: .init(2), activeHigh: false, value: false))
            } else { state = nil }
            _ = try library.append(cell.finish(area: area, state: state, context: &context), context: &context)
        }
        return try library.finish(source: source(sourceDigit), context: &context)
    }
    @available(macOS 26.0, *)
    private func chain(_ library: LogicTechnologyLibrary, base: Int = 0, context: inout LogicKernelContext) throws -> MappedGateDesign {
        var builder = try MappedGateBuilder(library: library,
            capacity: .init(nets: 3, instances: 2, pinConnections: 6, ports: 2, portBits: 2), context: &context)
        let origin = try LogicKernelSourceRange(artifactID: source(), byteRange: 10..<20)
        let y = try builder.addNet(.init(id: id(base + 1), driver: .instanceOutput(.init(1), .init(2)), origin: origin), context: &context)
        let middle = try builder.addNet(.init(id: id(base + 2), driver: .instanceOutput(.init(0), .init(2))), context: &context)
        let a = try builder.addNet(.init(id: id(base + 3), driver: .input), context: &context)
        _ = try builder.addInstance(id: id(base + 10), cell: .init(0), pinNets: [a, a, middle], origin: origin, context: &context)
        _ = try builder.addInstance(id: id(base + 11), cell: .init(0), pinNets: [middle, middle, y], context: &context)
        try builder.addPort(id: id(base + 20), direction: .input, nets: [a], context: &context)
        try builder.addPort(id: id(base + 21), direction: .output, nets: [y], context: &context)
        return try builder.finish(context: &context)
    }
    @available(macOS 26.0, *)
    private func evaluate(_ design: MappedGateDesign, input: Bool) throws -> Bool {
        try design.withTables { nets, instances, connections, _, _, order in
            var values = [Bool](repeating: false, count: nets.count)
            for offset in order.indices {
                guard case .net(let net) = order[offset] else { throw LogicKernelError.invalidModel("Reference expects combinational design") }
                switch nets[net.rawValue].driver {
                case .input: values[net.rawValue] = input
                case .constant(let value): values[net.rawValue] = value
                case .instanceOutput(let instanceIndex, let pin):
                    let instance = instances[instanceIndex.rawValue]
                    let cell = try design.library.cell(at: instance.cell)
                    let function = try #require(cell.pin(at: pin).function)
                    values[net.rawValue] = function.withOperations { operations in
                        var nodes = [Bool](repeating: false, count: operations.count)
                        for index in operations.indices {
                            switch operations[index] {
                            case .constant(let value): nodes[index] = value
                            case .input(let slot): nodes[index] = values[connections[instance.pins.lowerBound + slot].rawValue]
                            case .invert(let a): nodes[index] = !nodes[a.rawValue]
                            case .and(let a, let b): nodes[index] = nodes[a.rawValue] && nodes[b.rawValue]
                            case .or(let a, let b): nodes[index] = nodes[a.rawValue] || nodes[b.rawValue]
                            case .xor(let a, let b): nodes[index] = nodes[a.rawValue] != nodes[b.rawValue]
                            }
                        }
                        return nodes[function.output.rawValue]
                    }
                }
            }
            return values[0]
        }
    }

    @Test func reverseDeclarationAndRenamingPreserveActualCellMeaning() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        try exerciseMappedGraphContract()
        var run = try context()
        for kind in [Kind.buffer, .inverter, .nand] {
            let library = try library([kind], context: &run)
            for base in [0, 100] {
                let design = try chain(library, base: base, context: &run)
                #expect(design.netCount == 3 && design.instanceCount == 2 && design.stateCount == 0)
                let order = design.withTables { _, _, _, _, _, steps in Array(steps.indices.map { steps[$0] }) }
                #expect(order == [.net(.init(2)), .net(.init(1)), .net(.init(0))])
                for value in [false, true] { #expect(try evaluate(design, input: value) == value) }
                #expect(design.withTables { nets, _, _, _, _, _ in nets[0].origin?.byteRange } == 10..<20)
            }
        }
    }

    @Test func unreachableAndUnusedPinsDoNotInventFeedback() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for kind in [Kind.buffer, .nand] {
            var run = try context()
            let library = try library([kind], context: &run)
            var builder = try MappedGateBuilder(library: library,
                capacity: .init(nets: 2, instances: 1, pinConnections: 3, ports: 2, portBits: 2), context: &run)
            let y = try builder.addNet(.init(id: id(1), driver: .instanceOutput(.init(0), .init(2))), context: &run)
            let a = try builder.addNet(.init(id: id(2), driver: .input), context: &run)
            _ = try builder.addInstance(id: id(3), cell: .init(0), pinNets: [a, y, y], context: &run)
            try builder.addPort(id: id(4), direction: .input, nets: [a], context: &run)
            try builder.addPort(id: id(5), direction: .output, nets: [y], context: &run)
            if case .buffer = kind {
                let design = try builder.finish(context: &run)
                for value in [false, true] { #expect(try evaluate(design, input: value) == value) }
            } else {
                let before = run.usage[.managedStorageBytes]
                reject(builder, context: &run)
                #expect(run.usage[.managedStorageBytes] == before)
            }
        }
    }

    @Test func exactLibraryComparisonRejectsForgedIdentityAndAcceptsRebuild() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let original = try library([.buffer], context: &run)
        let design = try chain(original, context: &run)
        try design.validateLibrary(original, context: &run)
        let rebuilt = try library([.buffer], context: &run)
        try design.validateLibrary(rebuilt, context: &run)
        for library in [try library([.inverter], context: &run), try library([.buffer], sourceDigit: "34", context: &run),
                        try library([.buffer], area: 2, context: &run), try library([.buffer, .buffer], context: &run)] {
            #expect(throws: LogicKernelError.self) { try design.validateLibrary(library, context: &run) }
        }
    }

    @Test func flipFlopFeedbackIsCutAndLatchFeedbackIsRejected() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for kind in [Kind.ff(true), .latch(true)] {
            var run = try context()
            let library = try library([kind], context: &run)
            var builder = try MappedGateBuilder(library: library,
                capacity: .init(nets: 3, instances: 1, pinConnections: 4, ports: 2, portBits: 2), context: &run)
            let q = try builder.addNet(.init(id: id(1), driver: .instanceOutput(.init(0), .init(3))), context: &run)
            let clock = try builder.addNet(.init(id: id(2), driver: .input), context: &run)
            let reset = try builder.addNet(.init(id: id(3), driver: .constant(true)), context: &run)
            _ = try builder.addInstance(id: id(4), cell: .init(0), pinNets: [q, clock, reset, q], stateID: id(5), context: &run)
            try builder.addPort(id: id(6), direction: .input, nets: [clock], context: &run)
            try builder.addPort(id: id(7), direction: .output, nets: [q], context: &run)
            if case .ff = kind {
                let design = try builder.finish(context: &run)
                #expect(design.stateCount == 1)
                #expect(design.withTables { _, instances, _, _, _, _ in instances[0].initialValue } == nil)
                let order = design.withTables { _, _, _, _, _, steps in steps.indices.map { steps[$0] } }
                #expect(try #require(order.firstIndex(of: .state(.init(0)))) < #require(order.firstIndex(of: .net(q))))
                let wrongEdge = try self.library([.ff(false)], context: &run)
                #expect(throws: LogicKernelError.self) { try design.validateLibrary(wrongEdge, context: &run) }
            } else { reject(builder, context: &run) }
        }
    }

    @Test func clockGateFamilyAndPolarityProfilesAreEnforced() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for scenario in 0..<6 {
            var run = try context()
            let kinds: [Kind]
            switch scenario {
            case 0: kinds = [.ff(true), .ff(false)]
            case 1: kinds = [.latch(true), .latch(false)]
            case 2: kinds = [.ff(true), .latch(true)]
            case 3: kinds = [.ff(true), .ff(true)]
            case 4: kinds = [.latch(false), .latch(false)]
            default: kinds = [.ff(false), .ff(false)]
            }
            let library = try library(kinds, context: &run)
            var builder = try MappedGateBuilder(library: library,
                capacity: .init(nets: 5, instances: 2, pinConnections: 8, ports: 1, portBits: 2), context: &run)
            let clock = try builder.addNet(.init(id: id(1), driver: .input), context: &run)
            let other = try builder.addNet(.init(id: id(2), driver: .input), context: &run)
            let reset = try builder.addNet(.init(id: id(3), driver: .constant(true)), context: &run)
            let q0 = try builder.addNet(.init(id: id(4), driver: .instanceOutput(.init(0), .init(3))), context: &run)
            let q1 = try builder.addNet(.init(id: id(5), driver: .instanceOutput(.init(1), .init(3))), context: &run)
            _ = try builder.addInstance(id: id(10), cell: .init(0), pinNets: [reset, clock, reset, q0], stateID: id(20), initialValue: true, context: &run)
            _ = try builder.addInstance(id: id(11), cell: .init(1), pinNets: [reset, scenario == 3 ? other : clock, reset, q1], stateID: id(21), context: &run)
            try builder.addPort(id: id(30), direction: .input, nets: [clock, other], context: &run)
            if scenario < 4 { reject(builder, expected: 1, context: &run) }
            else {
                let design = try builder.finish(context: &run)
                #expect(design.stateCount == 2)
                #expect(design.withTables { _, instances, _, _, _, _ in instances[0].initialValue } == true)
            }
        }
    }

    @Test func malformedDriversPortsAndIdentitiesNeverPublish() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for scenario in 0..<9 {
            #expect(throws: LogicKernelError.self) {
                var run = try context()
                let library = try library([.buffer], context: &run)
                var builder = try MappedGateBuilder(library: library,
                    capacity: .init(nets: 3, instances: 1, pinConnections: 3, ports: 2, portBits: 2), context: &run)
                let y = try builder.addNet(.init(id: id(1), driver: .instanceOutput(.init(scenario == 0 ? 9 : 0), .init(scenario == 1 ? 0 : 2))), context: &run)
                let a = try builder.addNet(.init(id: id(scenario == 8 ? 1 : 2), driver: .input), context: &run)
                let extra = try builder.addNet(.init(id: id(3), driver: scenario == 7 ? .instanceOutput(.init(0), .init(2)) : .constant(false)), context: &run)
                _ = try builder.addInstance(id: id(4), cell: .init(0), pinNets: [scenario == 6 ? .init(99) : a, a, scenario == 2 ? extra : y], context: &run)
                if scenario != 3 {
                    try builder.addPort(id: id(scenario == 5 ? 4 : 5), direction: .input, nets: [scenario == 4 ? y : a], context: &run)
                }
                try builder.addPort(id: id(6), direction: .output, nets: [y], context: &run)
                return try builder.finish(context: &run)
            }
        }
    }

    @Test func failedAppendCapacitiesAndCancellationRemainExplicit() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let library = try library([.buffer], context: &run)
        var builder = try MappedGateBuilder(library: library,
            capacity: .init(nets: 1, instances: 1, pinConnections: 3, ports: 1, portBits: 1), context: &run)
        let net = try builder.addNet(.init(id: id(1), driver: .constant(true)), context: &run)
        for pins in [[], [net], [net, net, net, net]] {
            #expect(throws: LogicKernelError.self) { try builder.addInstance(id: id(2), cell: .init(0), pinNets: pins, context: &run) }
        }
        #expect(throws: LogicKernelError.self) {
            try builder.addInstance(id: id(2), cell: .init(0), pinNets: [net, net, net], initialValue: false, context: &run)
        }
        #expect(throws: LogicKernelError.self) { try builder.addPort(id: id(3), direction: .output, nets: [], context: &run) }
        try builder.addPort(id: id(3), direction: .output, nets: [net], context: &run)
        let design = try builder.finish(context: &run)
        #expect(design.instanceCount == 0 && design.portBitCount == 1)
        var tiny = try context(storage: 1)
        #expect(throws: LogicKernelError.self) {
            _ = try MappedGateBuilder(library: library, capacity: .init(nets: 1, instances: 0, pinConnections: 0, ports: 0, portBits: 0), context: &tiny)
        }
        #expect(tiny.usage[.allocationBytes] == 0)
        #expect(throws: LogicKernelError.self) { try MappedGraphCapacity(nets: -1, instances: 0, pinConnections: 0, ports: 0, portBits: 0) }
        let cancellation = LogicCancellationSource()
        var cancelled = try context(control: cancellation)
        let cancelledLibrary = try self.library([.buffer], context: &cancelled)
        let pending = try MappedGateBuilder(library: cancelledLibrary,
            capacity: .init(nets: 0, instances: 0, pinConnections: 0, ports: 0, portBits: 0), context: &cancelled)
        cancellation.cancel()
        reject(pending, expected: 2, context: &cancelled)
        #expect(throws: LogicKernelError.cancelled) { try design.validateLibrary(library, context: &cancelled) }
        var enormous = LogicKernelContext(limits: try .init(maximums:
            Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64.max) })), control: Control())
        #expect(throws: LogicKernelError.self) {
            _ = try MappedGateBuilder(library: library,
                capacity: .init(nets: Int.max, instances: Int.max, pinConnections: 0, ports: 0, portBits: 0), context: &enormous)
        }
        #expect(enormous.usage[.allocationBytes] == 0)
    }
    @available(macOS 26.0, *)
    @Test func actualNetlistCodecsRoundTripAndReadPhysicalConnections() throws {
        var context = try context()
        let library = try library([.nand], context: &context)
        let original = try chain(library, context: &context)
        let codec: any MappedGateDesignCoding = MappedGateDesignCodec()
        let verilog: any MappedGateVerilogCoding = MappedGateVerilogCodec()
        let data = try codec.encode(original)
        let decoded = try codec.decode(data, library: library, context: &context)
        #expect(try codec.encode(decoded) == data)
        let source = try verilog.encode(original, top: "top")
        let imported = try verilog.decode(source, identities: decoded, top: "top", context: &context)
        #expect(try codec.encode(imported) == data)
        for input in [false, true] { #expect(try evaluate(imported, input: input) == input) }
        let changed = String(decoding: source, as: UTF8.self).replacingOccurrences(of: "assign p1_0=n0;", with: "assign p1_0=n1;")
        let rewired = try verilog.decode(Data(changed.utf8), identities: decoded, top: "top", context: &context)
        #expect(try codec.encode(rewired) != data)
        #expect(rewired.withTables { _, _, _, ports, bits, _ in bits[ports[1].bits.lowerBound].rawValue == 1 })
    }

    @available(macOS 26.0, *)
    @Test func actualCodecRefusesForeignLibraryAndMalformedPhysicalPins() throws {
        var context = try context()
        let library = try library([.nand], context: &context)
        let design = try chain(library, context: &context)
        let data = try MappedGateDesignCodec().encode(design)
        let foreign = try self.library([.nand], sourceDigit: "34", context: &context)
        #expect(throws: LogicKernelError.self) { try MappedGateDesignCodec().decode(data, library: foreign, context: &context) }
        let source = String(decoding: try MappedGateVerilogCodec().encode(design, top: "top"), as: UTF8.self)
        for malformed in [source.replacingOccurrences(of: "\\Y ", with: "\\BAD "),
                          source + "module extra;endmodule", source.replacingOccurrences(of: "wire n0;", with: "wire n999;")] {
            #expect(throws: LogicKernelError.self) {
                try MappedGateVerilogCodec().decode(Data(malformed.utf8), identities: design, top: "top", context: &context)
            }
        }
        let old = Data(#"{"schemaVersion":1,"mappedCell":"C0"}"#.utf8)
        #expect(throws: (any Error).self) { try MappedGateDesignCodec().decode(old, library: library, context: &context) }
    }

    @available(macOS 26.0, *)
    @Test func realizationPoliciesPreserveStartupAndRequireActualTieCells() throws {
        try exerciseMappedRealizationContract()
    }

    @available(macOS 26.0, *)
    @Test func standardConstantBytesRetainLogicalDriversWithoutInventingTieCells() throws {
        var context = try context()
        let library = try library([.buffer], context: &context)
        for value in [false, true] {
            var builder = try MappedGateBuilder(library: library,
                capacity: .init(nets: 1, instances: 0, pinConnections: 0, ports: 1, portBits: 1), context: &context)
            let net = try builder.addNet(.init(id: id(1), driver: .constant(value)), context: &context)
            try builder.addPort(id: id(2), direction: .output, nets: [net], context: &context)
            let logical = try builder.finish(context: &context)
            let bytes = try MappedGateVerilogCodec().encode(logical, top: "constant")
            #expect(String(decoding: bytes, as: UTF8.self).contains("assign n0=1'b\(value ? 1 : 0);"))
            let decoded = try MappedGateVerilogCodec().decode(bytes, identities: logical, top: "constant", context: &context)
            #expect(decoded.instanceCount == 0)
            #expect(decoded.withTables { nets, _, _, _, _, _ in nets[0].driver == .constant(value) })
            #expect(try MappedGateDesignCodec().encode(decoded) == MappedGateDesignCodec().encode(logical))
        }
    }

    @available(macOS 26.0, *)
    private func sequential(_ library: LogicTechnologyLibrary, initial: Bool?,
                            context: inout LogicKernelContext) throws -> MappedGateDesign {
        var builder = try MappedGateBuilder(library: library, capacity: .init(nets: 4, instances: 1,
            pinConnections: 4, ports: 2, portBits: 4), context: &context)
        for n in 0..<3 { _ = try builder.addNet(.init(id: id(n + 1), driver: .input), context: &context) }
        _ = try builder.addNet(.init(id: id(4), driver: .instanceOutput(.init(0), .init(3))), context: &context)
        _ = try builder.addInstance(id: id(10), cell: .init(0), pinNets: [.init(0),.init(1),.init(2),.init(3)],
                                    stateID: id(99), initialValue: initial, context: &context)
        try builder.addPort(id: id(20), direction: .input, nets: [.init(0),.init(1),.init(2)], context: &context)
        try builder.addPort(id: id(21), direction: .output, nets: [.init(3)], context: &context)
        return try builder.finish(context: &context)
    }

    @available(macOS 26.0, *)
    @Test func standardSequentialNetlistRefusesUnrealizedStartupAndPreservesAbstractInitials() throws {
        var context = try context()
        for kind in [Kind.ff(false), .latch(true)] {
            let library = try library([kind], context: &context)
            let unspecified = try sequential(library, initial: nil, context: &context)
            let verilog = try MappedGateVerilogCodec().encode(unspecified, top: "sequential")
            let imported = try MappedGateVerilogCodec().decode(verilog, identities: unspecified,
                                                             top: "sequential", context: &context)
            #expect(try MappedGateDesignCodec().encode(imported) == MappedGateDesignCodec().encode(unspecified))
            for initial in [false, true] {
                let abstract = try sequential(library, initial: initial, context: &context)
                let json = try MappedGateDesignCodec().encode(abstract)
                let decoded = try MappedGateDesignCodec().decode(json, library: library, context: &context)
                #expect(decoded.withTables { _, instances, _, _, _, _ in
                    instances[0].stateID?.rawValue == 99 && instances[0].initialValue == initial
                })
                #expect(throws: LogicKernelError.unsupported("Mapped instance 10 demands initial state \(initial ? 1 : 0); the cell has no physical startup realization")) {
                    try MappedGateVerilogCodec().encode(decoded, top: "sequential")
                }
                #expect(throws: LogicKernelError.unsupported("Mapped instance 10 demands initial state \(initial ? 1 : 0); the cell has no physical startup realization")) {
                    try MappedGateVerilogCodec().decode(verilog, identities: decoded,
                                                      top: "sequential", context: &context)
                }
            }
        }
    }

}
