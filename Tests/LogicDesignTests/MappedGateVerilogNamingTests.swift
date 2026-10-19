import CircuiteFoundation
import Foundation
import LogicDesignSerialization
import LogicIR
import LogicKernelCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct MappedGateVerilogNamingTests {
    private struct Running: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private func context(work: UInt64 = 10_000_000, storage: UInt64 = 10_000_000,
                         output: UInt64 = 10_000_000, control: any LogicRunControlling = Running()) throws -> LogicKernelContext {
        var maximums = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        maximums[.workUnits] = work; maximums[.managedStorageBytes] = storage; maximums[.outputBytes] = output
        return .init(limits: try .init(maximums: maximums), control: control)
    }
    private func id(_ value: UInt64) throws -> DesignEntityID { try .init(rawValue: value) }
    @available(macOS 26.0, *)
    private func graph(cellName: String = "gate:inv", context: inout LogicKernelContext) throws -> MappedGateDesign {
        var function = try LogicBooleanFunctionBuilder(inputCount: 2, nodeCapacity: 2, context: &context)
        let input = try function.append(.input(0), context: &context)
        let inverted = try function.append(.invert(input), context: &context)
        let body = try function.finish(output: inverted, context: &context)
        var cell = try LogicTechnologyCellBuilder(id: id(100), name: cellName, pinCapacity: 2, context: &context)
        _ = try cell.append(.init(id: id(101), name: "in[0]", direction: .input), context: &context)
        _ = try cell.append(.init(id: id(102), name: "out/Y", direction: .output, function: body), context: &context)
        var library = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 2, context: &context)
        _ = try library.append(cell.finish(area: 1, state: nil, context: &context), context: &context)
        let source = try ArtifactID(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "12", count: 32)), byteCount: 100)
        let cells = try library.finish(source: source, context: &context)
        var design = try MappedGateBuilder(library: cells,
            capacity: .init(nets: 3, instances: 2, pinConnections: 4, ports: 2, portBits: 2), context: &context)
        let a = try design.addNet(.init(id: id(1), driver: .input), context: &context)
        let middle = try design.addNet(.init(id: id(2), driver: .instanceOutput(.init(0), .init(1))), context: &context)
        let y = try design.addNet(.init(id: id(3), driver: .instanceOutput(.init(1), .init(1))), context: &context)
        _ = try design.addInstance(id: id(10), cell: .init(0), pinNets: [a, middle], context: &context)
        _ = try design.addInstance(id: id(11), cell: .init(0), pinNets: [middle, y], context: &context)
        try design.addPort(id: id(20), direction: .input, nets: [a], context: &context)
        try design.addPort(id: id(21), direction: .output, nets: [y], context: &context)
        return try design.finish(context: &context)
    }
    private func naming(instances: [DesignEntityID: String]? = nil, nets: [DesignEntityID: String]? = nil,
                        ports: [DesignEntityID: [String]]? = nil) throws -> MappedGateVerilogNaming {
        try .init(instanceNames: instances ?? [id(10): "cts_net-4_cell-0/CLK", id(11): "sink:Q[0]"],
                  netNames: nets ?? [id(1): "a", id(2): "route-1/internal", id(3): "out:Y"],
                  portBitNames: ports ?? [id(20): ["a"], id(21): ["y[0]"]])
    }
    @available(macOS 26.0, *)
    private func evaluate(_ design: MappedGateDesign, input: Bool) throws -> Bool {
        try design.withTables { nets, instances, connections, ports, bits, order in
            var values = [Bool](repeating: false, count: nets.count)
            for offset in order.indices {
                let step = order[offset]
                guard case .net(let net) = step else { throw LogicKernelError.unsupported("Test reference is combinational") }
                switch nets[net.rawValue].driver {
                case .input: values[net.rawValue] = input
                case .constant(let bit): values[net.rawValue] = bit
                case .instanceOutput(let instanceIndex, let pin):
                    let instance = instances[instanceIndex.rawValue]
                    let cell = try design.library.cell(at: instance.cell)
                    let function = try #require(cell.pin(at: pin).function)
                    values[net.rawValue] = function.withOperations { operations in
                        var nodes = [Bool](repeating: false, count: operations.count)
                        for index in operations.indices {
                            switch operations[index] {
                            case .constant(let bit): nodes[index] = bit
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
            return values[bits[ports[1].bits.lowerBound].rawValue]
        }
    }

    @available(macOS 26.0, *)
    @Test func exactEscapedNamesAndSharedPortNetRoundTripThroughProtocol() throws {
        var setup = try context()
        let design = try graph(context: &setup), names = try naming()
        let codec: any MappedGateVerilogCoding = MappedGateVerilogCodec()
        var run = try context()
        let bytes = try codec.encode(design, top: "top-name", naming: names, context: &run)
        let text = String(decoding: bytes, as: UTF8.self)
        var intake = try context()
        let structural = try MappedGateVerilogCodec().decodeSource(bytes, top: "top-name", context: &intake)
        #expect(structural.instances.map(\.name) == ["cts_net-4_cell-0/CLK", "sink:Q[0]"])
        #expect(structural.instances[0].connections.map(\.netName) == ["a", "route-1/internal"])
        #expect(text.contains("\\cts_net-4_cell-0/CLK ") && text.contains("\\sink:Q[0] "))
        #expect(text.contains("\\route-1/internal ") && text.contains("\\out:Y ") && text.contains("\\y[0] "))
        #expect(text.contains("input \\a ;") && !text.contains("wire \\a ;") && !text.contains("assign \\a =\\a ;"))
        #expect(run.usage[.outputBytes] == UInt64(bytes.count))
        #expect(run.usage[.managedStorageBytes] == UInt64(bytes.count + MemoryLayout<Data>.stride))
        let imported = try codec.decode(bytes, identities: design, top: "top-name", naming: names, context: &run)
        #expect(try MappedGateDesignCodec().encode(imported) == MappedGateDesignCodec().encode(design))
        for bit in [false, true] {
            #expect(try evaluate(imported, input: bit) == evaluate(design, input: bit))
            #expect(try evaluate(imported, input: bit) == bit)
        }
        let second = try codec.encode(imported, top: "top-name", naming: names, context: &run)
        #expect(second == bytes)
    }

    @available(macOS 26.0, *)
    @Test func actualTextRewiringIsReadRatherThanRecoveredFromSidecar() throws {
        var setup = try context()
        let design = try graph(context: &setup), names = try naming(), codec = MappedGateVerilogCodec()
        var run = try context()
        let bytes = try codec.encode(design, top: "top", naming: names, context: &run)
        let changed = String(decoding: bytes, as: UTF8.self).replacingOccurrences(
            of: "assign \\y[0] =\\out:Y ;", with: "assign \\y[0] =\\route-1/internal ;")
        #expect(changed != String(decoding: bytes, as: UTF8.self))
        let imported = try codec.decode(Data(changed.utf8), identities: design, top: "top", naming: names, context: &run)
        #expect(try MappedGateDesignCodec().encode(imported) != MappedGateDesignCodec().encode(design))
        for bit in [false, true] { #expect(try evaluate(imported, input: bit) != evaluate(design, input: bit)) }
    }

    @available(macOS 26.0, *)
    @Test func duplicateForeignMissingConflictingAndInvalidNamesRefuseBothDirections() throws {
        var setup = try context()
        let design = try graph(context: &setup), names = try naming(), codec = MappedGateVerilogCodec()
        let bytes = try codec.encode(design, top: "top", naming: names, context: &setup)
        let variants = try [
            naming(instances: [id(10): "same", id(11): "same"]),
            naming(instances: [id(10): "a", id(11): "second"]),
            naming(instances: [id(10): "one"]),
            naming(instances: [id(999): "one", id(11): "two"]),
            naming(nets: [id(1): "same", id(2): "same", id(3): "y"]),
            naming(nets: [id(1): "a", id(2): "middle"]),
            naming(ports: [id(20): ["out:Y"], id(21): ["y"]]),
            naming(ports: [id(20): ["a"], id(21): ["a"]]),
            naming(ports: [id(20): ["a", "extra"], id(21): ["y"]]),
            naming(ports: [id(999): ["a"], id(21): ["y"]])
        ]
        for invalid in variants {
            var run = try context()
            #expect(throws: LogicKernelError.self) { try codec.encode(design, top: "top", naming: invalid, context: &run) }
            #expect(throws: LogicKernelError.self) { try codec.decode(bytes, identities: design, top: "top", naming: invalid, context: &run) }
            #expect(run.usage[.allocationBytes] == 0)
        }
        for value in ["", "with space", "with\ttab", "line\nbreak", "nonascii-é", "control\u{7f}"] {
            let invalid = try naming(instances: [id(10): value, id(11): "other"])
            var run = try context()
            #expect(throws: LogicKernelError.self) { try codec.encode(design, top: "top", naming: invalid, context: &run) }
            #expect(run.usage[.allocationBytes] == 0)
        }
    }

    @available(macOS 26.0, *)
    @Test func escapedKeywordsRemainIdentifiersAndSyntaxCannotBeEscaped() throws {
        var setup = try context()
        let design = try graph(cellName: "assign", context: &setup)
        let names = try naming(instances: [id(10): "module", id(11): "wire"],
            nets: [id(1): "input", id(2): "assign", id(3): "output"], ports: [id(20): ["input"], id(21): ["endmodule"]])
        let codec = MappedGateVerilogCodec(), bytes = try codec.encode(design, top: "module", naming: names, context: &setup)
        let imported = try codec.decode(bytes, identities: design, top: "module", naming: names, context: &setup)
        #expect(try MappedGateDesignCodec().encode(imported) == MappedGateDesignCodec().encode(design))
        let invalid = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "module \\module ", with: "\\module  \\module ")
        #expect(throws: LogicKernelError.self) {
            try codec.decode(Data(invalid.utf8), identities: design, top: "module", naming: names, context: &setup)
        }
    }

    @available(macOS 26.0, *)
    private struct LegacyOnly: MappedGateVerilogCoding {
        func encode(_ design: borrowing MappedGateDesign, top: String) throws -> Data {
            try MappedGateVerilogCodec().encode(design, top: top)
        }
        func decode(_ data: Data, identities: borrowing MappedGateDesign, top: String,
                    context: inout LogicKernelContext) throws -> MappedGateDesign {
            try MappedGateVerilogCodec().decode(data, identities: identities, top: top, context: &context)
        }
    }

    @available(macOS 26.0, *)
    @Test func legacyBytesAndExternalConformerBehaviorRemainExplicit() throws {
        var run = try context()
        let design = try graph(context: &run), names = try naming()
        let codec: any MappedGateVerilogCoding = MappedGateVerilogCodec()
        let expected = #"""
        module \top (p0_0,p1_0);
        input p0_0;
        output p1_0;
        wire n0;
        wire n1;
        wire n2;
        assign n0=p0_0;
        assign p1_0=n2;
        \gate:inv i0(.\in[0] (n0),.\out/Y (n1));
        \gate:inv i1(.\in[0] (n1),.\out/Y (n2));
        endmodule
        """# + "\n"
        let bytes = try codec.encode(design, top: "top")
        #expect(bytes == Data(expected.utf8))
        var intake = try context()
        let structural = try MappedGateVerilogCodec().decodeSource(bytes, top: "top", context: &intake)
        #expect(structural.instances.map(\.name) == ["i0", "i1"] && structural.aliases.count == 2)
        #expect(structural.instances[1].connections.map(\.netName) == ["n1", "n2"])
        let imported = try codec.decode(bytes, identities: design, top: "top", context: &run)
        #expect(try MappedGateDesignCodec().encode(imported) == MappedGateDesignCodec().encode(design))
        let external: any MappedGateVerilogCoding = LegacyOnly()
        #expect(try external.encode(design, top: "top") == bytes)
        #expect(throws: LogicKernelError.unsupported("This codec does not implement identity-bound Verilog naming")) {
            try external.encode(design, top: "top", naming: names, context: &run)
        }
        #expect(throws: LogicKernelError.unsupported("This codec does not implement identity-bound Verilog naming")) {
            try external.decode(bytes, identities: design, top: "top", naming: names, context: &run)
        }
    }

    @available(macOS 26.0, *)
    @Test func rawLibraryIdentifierTraversalRequiresWorkBeforeCharacterValidation() throws {
        var setup = try context()
        let design = try graph(cellName: String(repeating: "x", count: 20_000) + " ", context: &setup)
        let names = try naming(), codec = MappedGateVerilogCodec()
        var run = try context(work: 10_000)
        do {
            _ = try codec.encode(design, top: "top", naming: names, context: &run)
            Issue.record("Raw library identifier traversal bypassed the work budget")
        } catch let error as LogicKernelError {
            guard case .resourceLimit(let resource, _, _) = error else {
                Issue.record("Character validation ran before work admission: \(error)"); return
            }
            #expect(resource == .workUnits)
        }
        #expect(run.usage[.allocationBytes] == 0 && run.usage[.outputBytes] == 0)
    }

    @available(macOS 26.0, *)
    @Test func outputWorkStorageAndCancellationQuotasPrecedeAllocationAndRemainCumulative() throws {
        var setup = try context()
        let design = try graph(context: &setup), names = try naming(), codec = MappedGateVerilogCodec()
        let bytes = try codec.encode(design, top: "top", naming: names, context: &setup)
        for mode in 0..<3 {
            var run = try context(work: mode == 0 ? 1 : 10_000_000,
                storage: mode == 1 ? 1 : 10_000_000, output: mode == 2 ? 1 : 10_000_000)
            #expect(throws: LogicKernelError.self) { try codec.encode(design, top: "top", naming: names, context: &run) }
            #expect(run.usage[.allocationBytes] == 0)
        }
        for mode in 0..<2 {
            var run = try context(work: mode == 0 ? 1 : 10_000_000, storage: mode == 1 ? 1 : 10_000_000)
            #expect(throws: LogicKernelError.self) { try codec.decode(bytes, identities: design, top: "top", naming: names, context: &run) }
            #expect(run.usage[.allocationBytes] == 0)
        }
        let cancellation = LogicCancellationSource()
        var cancelled = try context(control: cancellation)
        cancellation.cancel()
        #expect(throws: LogicKernelError.cancelled) { try codec.encode(design, top: "top", naming: names, context: &cancelled) }
        #expect(throws: LogicKernelError.cancelled) { try codec.decode(bytes, identities: design, top: "top", naming: names, context: &cancelled) }
        var cumulative = try context(output: UInt64(bytes.count * 2 - 1))
        _ = try codec.encode(design, top: "top", naming: names, context: &cumulative)
        let allocated = cumulative.usage[.allocationBytes]
        #expect(throws: LogicKernelError.self) { try codec.encode(design, top: "top", naming: names, context: &cumulative) }
        #expect(cumulative.usage[.outputBytes] == UInt64(bytes.count) && cumulative.usage[.allocationBytes] == allocated)
        var malformed = try context()
        #expect(throws: LogicKernelError.self) {
            try codec.decode(bytes + Data("trailing".utf8), identities: design, top: "top", naming: names, context: &malformed)
        }
        #expect(malformed.usage[.managedStorageBytes] == 0)
    }
}
