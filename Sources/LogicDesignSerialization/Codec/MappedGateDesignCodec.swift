import CircuiteFoundation
import CircuiteFoundationFoundation
import Foundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public struct MappedGateDesignCodec: MappedGateDesignCoding {
    public init() {}

    public func encode(_ design: borrowing MappedGateDesign) throws -> Data {
        let record = try design.withTables { nets, instances, pins, ports, bits, _ in
            var nr: [Net] = []; var ir: [Instance] = []; var pr: [Port] = []
            for n in nets.indices {
                let value = nets[n]; let driver: Driver
                switch value.driver {
                case .input: driver = .input
                case .constant(let v): driver = .constant(v)
                case .instanceOutput(let i, let p): driver = .output(i.rawValue, p.rawValue)
                }
                nr.append(.init(id: value.id, driver: driver, origin: value.origin.map(Origin.init)))
            }
            for i in instances.indices {
                let value = instances[i]; let cell = try design.library.cell(at: value.cell)
                var connections: [Int] = []; var names: [String] = []
                for p in 0..<cell.pinCount {
                    names.append(try cell.pin(at: .init(p)).name)
                    connections.append(pins[value.pins.lowerBound + p].rawValue)
                }
                ir.append(.init(id: value.id, cellID: cell.id, cellName: cell.name,
                    pinNames: names, nets: connections, stateID: value.stateID,
                    initial: value.initialValue, origin: value.origin.map(Origin.init)))
            }
            for p in ports.indices {
                let value = ports[p]; var connections: [Int] = []
                for b in value.bits { connections.append(bits[b].rawValue) }
                pr.append(.init(id: value.id, input: value.direction == .input, nets: connections))
            }
            return Record(schemaVersion: 1, representation: "mapped-gates", library: design.library.source,
                          nets: nr, instances: ir, ports: pr)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(record)
    }

    public func decode(_ data: Data, library: borrowing LogicTechnologyLibrary,
                       context: inout LogicKernelContext) throws -> MappedGateDesign {
        try context.charge(.expansion, amount: UInt64(data.count))
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.schemaVersion == 1, record.representation == "mapped-gates",
              record.library == library.source else {
            throw LogicKernelError.invalidInput("Mapped schema or exact library source differs")
        }
        var cells: [DesignEntityID: Int] = [:]
        try library.withCells { values in
            for c in values.indices {
                guard cells.updateValue(c, forKey: values[c].id) == nil else {
                    throw LogicKernelError.invalidModel("Duplicate library cell identity")
                }
            }
        }
        var pinCount = 0; var bitCount = 0
        for instance in record.instances { pinCount = try sum(pinCount, instance.nets.count) }
        for port in record.ports { bitCount = try sum(bitCount, port.nets.count) }
        var builder = try MappedGateBuilder(library: copy library,
            capacity: MappedGraphCapacity(nets: record.nets.count, instances: record.instances.count,
                pinConnections: pinCount, ports: record.ports.count, portBits: bitCount), context: &context)
        for net in record.nets {
            let driver: MappedGateNet.Driver
            switch net.driver {
            case .input: driver = .input
            case .constant(let v): driver = .constant(v)
            case .output(let i, let p): driver = .instanceOutput(.init(i), .init(p))
            }
            _ = try builder.addNet(.init(id: net.id, driver: driver, origin: try net.origin?.value()), context: &context)
        }
        for instance in record.instances {
            guard let index = cells[instance.cellID] else { throw LogicKernelError.invalidModel("Unknown serialized cell") }
            let cell = try library.cell(at: .init(index))
            guard instance.cellName == cell.name, instance.nets.count == cell.pinCount,
                  instance.pinNames.count == cell.pinCount else { throw LogicKernelError.invalidModel("Cell identity or pin count differs") }
            for p in instance.pinNames.indices {
                guard instance.pinNames[p] == (try cell.pin(at: .init(p)).name) else {
                    throw LogicKernelError.invalidModel("Physical pin identity differs")
                }
            }
            _ = try builder.addInstance(id: instance.id, cell: .init(index),
                pinNets: instance.nets.map(MappedNetIndex.init), stateID: instance.stateID,
                initialValue: instance.initial, origin: try instance.origin?.value(), context: &context)
        }
        for port in record.ports {
            try builder.addPort(id: port.id, direction: port.input ? .input : .output,
                                nets: port.nets.map(MappedNetIndex.init), context: &context)
        }
        return try builder.finish(context: &context)
    }

    private func sum(_ lhs: Int, _ rhs: Int) throws -> Int {
        let value = lhs.addingReportingOverflow(rhs)
        guard !value.overflow else { throw LogicKernelError.invalidInput("Serialized capacity overflows") }
        return value.partialValue
    }
    private struct Record: Codable {
        let schemaVersion: Int
        let representation: String
        let library: ArtifactID
        let nets: [Net]
        let instances: [Instance]
        let ports: [Port]
    }
    private enum Driver: Codable { case input, constant(Bool), output(Int, Int) }
    private struct Net: Codable { let id: DesignEntityID; let driver: Driver; let origin: Origin? }
    private struct Instance: Codable {
        let id: DesignEntityID
        let cellID: DesignEntityID
        let cellName: String
        let pinNames: [String]
        let nets: [Int]
        let stateID: DesignEntityID?
        let initial: Bool?
        let origin: Origin?
    }
    private struct Port: Codable { let id: DesignEntityID; let input: Bool; let nets: [Int] }
    private struct Origin: Codable {
        let artifact: ArtifactID; let start: UInt64; let end: UInt64
        init(_ value: LogicKernelSourceRange) {
            artifact = value.artifactID; start = value.byteRange.lowerBound; end = value.byteRange.upperBound
        }
        func value() throws -> LogicKernelSourceRange {
            guard start <= end else { throw LogicKernelError.invalidModel("Reversed origin range") }
            return try .init(artifactID: artifact, byteRange: start..<end)
        }
    }
}
