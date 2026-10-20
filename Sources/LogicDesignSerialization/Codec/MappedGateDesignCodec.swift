import CircuiteFoundation
import CircuiteFoundationFoundation
import Foundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public struct MappedGateDesignCodec: MappedGateDesignControlledCoding {
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

    // Keep the returned retention anchor with the value and all escaped copies.
    public func encodeControlled(_ design: borrowing MappedGateDesign, context: inout LogicKernelContext)
        throws -> (value: Data, retention: LogicKernelRetention) {
        let scope = try context.beginRetentionScope()
        do {
            let failureMetadata = try context.reserveStorage(byteCount: UInt64(MemoryLayout<LogicGraphCodecSourceFailure>.stride))
            let workspace = try encodingWorkspace(design, context: &context)
            try context.charge(.workUnits, amount: UInt64(workspace))
            let temporary = try LogicGraphJSONSize.reserve(workspace, context: &context)
            let value = try encodeAdmitted(design, context: &context)
            try context.releaseStorage(temporary)
            try context.releaseStorage(failureMetadata)
            return (value, try context.finishRetentionScope(scope))
        } catch {
            try LogicGraphCodecSourceFailure.rethrow(error, scope: scope, context: &context)
        }
    }

    // Keep the returned retention anchor with the value and all escaped copies.
    public func decodeControlled(_ data: Data, library: borrowing LogicTechnologyLibrary, context: inout LogicKernelContext)
        throws -> (value: MappedGateDesign, retention: LogicKernelRetention) {
        let scope = try context.beginRetentionScope()
        do {
            let failureMetadata = try context.reserveStorage(byteCount: UInt64(MemoryLayout<LogicGraphCodecSourceFailure>.stride))
            let counts = try LogicGraphJSONPreflight.inspect(data, schema: .mapped, context: &context)
            var bytes = LogicGraphJSONSize()
            try bytes.add(try decodingWorkspace(counts, library: library))
            let conversion = try LogicGraphJSONSize.decodedStrings(counts)
            try bytes.add(conversion)
            try context.charge(.workUnits, amount: UInt64(conversion))
            let temporary = try LogicGraphJSONSize.reserve(bytes.value, context: &context)
            _ = try LogicGraphJSONSize.reserve(try LogicGraphJSONSize.decodedArtifactBacking(counts), context: &context)
            let value = try decodeAdmitted(data, library: library, context: &context, controlled: true)
            try context.releaseStorage(temporary)
            try context.releaseStorage(failureMetadata)
            return (value, try context.finishRetentionScope(scope))
        } catch {
            try LogicGraphCodecSourceFailure.rethrow(error, scope: scope, context: &context)
        }
    }

    private func decodingWorkspace(_ counts: LogicGraphJSONPreflight.Counts, library: borrowing LogicTechnologyLibrary) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(MemoryLayout<Record>.stride)
        try size.array(counts.nets, of: Net.self); try size.array(counts.instances, of: Instance.self)
        try size.array(counts.ports, of: Port.self); try size.array(counts.pinNames, of: String.self)
        try size.array(counts.connections, of: Int.self)
        try size.array(counts.connections, of: MappedNetIndex.self)
        try size.add(MemoryLayout<[MappedNetIndex]>.stride)
        try size.add(MemoryLayout<[DesignEntityID: Int]>.stride)
        let cells = library.withCells { $0.count }
        try size.add(LogicGraphJSONPreflight.multiply(cells, MemoryLayout<DesignEntityID>.stride + MemoryLayout<Int>.stride))
        return size.value
    }
    private func encodingWorkspace(_ design: borrowing MappedGateDesign, context: inout LogicKernelContext) throws -> Int {
        try design.withTables { nets, instances, _, ports, _, _ in
            var size = LogicGraphJSONSize(); try size.add(MemoryLayout<Record>.stride)
            try size.array(nets.count, of: Net.self); try size.array(instances.count, of: Instance.self)
            try size.array(ports.count, of: Port.self)
            var ids = try LogicGraphJSONPreflight.add(nets.count, ports.count)
            try size.add(try LogicGraphJSONSize.encodedArtifactScratch(design.library.source))
            for n in nets.indices {
                try context.charge(.workUnits)
                if let origin = nets[n].origin { try size.add(try LogicGraphJSONSize.encodedArtifactScratch(origin.artifactID)) }
            }
            for i in instances.indices {
                try context.charge(.workUnits)
                let value = instances[i]; let cell = try design.library.cell(at: value.cell)
                try size.array(cell.pinCount, of: Int.self); try size.array(cell.pinCount, of: String.self)
                ids = try LogicGraphJSONPreflight.add(ids, value.stateID == nil ? 2 : 3)
                if let origin = value.origin { try size.add(try LogicGraphJSONSize.encodedArtifactScratch(origin.artifactID)) }
            }
            for p in ports.indices { try context.charge(.workUnits); try size.array(ports[p].bits.count, of: Int.self) }
            try size.add(try LogicGraphJSONSize.encodedIdentifierScratch(ids))
            return size.value
        }
    }
    private func encodedSize(_ record: Record, context: inout LogicKernelContext) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(LogicGraphJSONSize.objectHeader(6))
        try size.field("schemaVersion", 1); try size.field("representation", LogicGraphJSONSize.quoted("mapped-gates"))
        try size.field("library", LogicGraphJSONSize.artifact(record.library))
        var nets = LogicGraphJSONSize(); try nets.add(try LogicGraphJSONSize.arrayHeader(record.nets.count))
        for net in record.nets {
            try context.charge(.workUnits)
            var row = LogicGraphJSONSize(); try row.add(LogicGraphJSONSize.objectHeader(net.origin == nil ? 2 : 3))
            try row.field("id", 18); try row.field("driver", driverSize(net.driver))
            if let origin = net.origin { try row.field("origin", originSize(origin)) }
            try nets.add(row.value)
        }
        try size.field("nets", nets.value)
        var instances = LogicGraphJSONSize(); try instances.add(try LogicGraphJSONSize.arrayHeader(record.instances.count))
        for instance in record.instances {
            try context.charge(.workUnits)
            var row = LogicGraphJSONSize(); try row.add(LogicGraphJSONSize.objectHeader(5 + (instance.stateID == nil ? 0 : 1) + (instance.initial == nil ? 0 : 1) + (instance.origin == nil ? 0 : 1)))
            try row.field("id", 18); try row.field("cellID", 18)
            try row.field("cellName", LogicGraphJSONSize.string(instance.cellName, context: &context))
            var names = LogicGraphJSONSize(); try names.add(try LogicGraphJSONSize.arrayHeader(instance.pinNames.count))
            for name in instance.pinNames { try names.add(try LogicGraphJSONSize.string(name, context: &context)) }
            try row.field("pinNames", names.value)
            try row.field("nets", integerArraySize(instance.nets, context: &context))
            if instance.stateID != nil { try row.field("stateID", 18) }
            if let initial = instance.initial { try row.field("initial", LogicGraphJSONSize.boolean(initial)) }
            if let origin = instance.origin { try row.field("origin", originSize(origin)) }
            try instances.add(row.value)
        }
        try size.field("instances", instances.value)
        var ports = LogicGraphJSONSize(); try ports.add(try LogicGraphJSONSize.arrayHeader(record.ports.count))
        for port in record.ports {
            try context.charge(.workUnits)
            var row = LogicGraphJSONSize(); try row.add(LogicGraphJSONSize.objectHeader(3))
            try row.field("id", 18); try row.field("input", LogicGraphJSONSize.boolean(port.input))
            try row.field("nets", integerArraySize(port.nets, context: &context)); try ports.add(row.value)
        }
        try size.field("ports", ports.value)
        return size.value
    }
    private func integerArraySize(_ values: [Int], context: inout LogicKernelContext) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(try LogicGraphJSONSize.arrayHeader(values.count))
        for value in values { try context.charge(.workUnits); try size.add(LogicGraphJSONSize.integer(value)) }
        return size.value
    }
    private func originSize(_ value: Origin) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(LogicGraphJSONSize.objectHeader(3))
        try size.field("artifact", LogicGraphJSONSize.artifact(value.artifact))
        try size.field("start", LogicGraphJSONSize.unsigned(value.start)); try size.field("end", LogicGraphJSONSize.unsigned(value.end))
        return size.value
    }
    private func driverSize(_ driver: Driver) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(2)
        switch driver {
        case .input: try size.field("input", 2)
        case .constant(let value):
            var payload = LogicGraphJSONSize(); try payload.add(2); try payload.field("_0", LogicGraphJSONSize.boolean(value))
            try size.field("constant", payload.value)
        case .output(let instance, let pin):
            var payload = LogicGraphJSONSize(); try payload.add(LogicGraphJSONSize.objectHeader(2))
            try payload.field("_0", LogicGraphJSONSize.integer(instance)); try payload.field("_1", LogicGraphJSONSize.integer(pin))
            try size.field("output", payload.value)
        }
        return size.value
    }

    private func indices<Element>(_ values: [Int], range: Range<Int>, controlled: Bool,
        context: inout LogicKernelContext, transform: (Int) -> Element) throws(LogicKernelError) -> [Element] {
        if !controlled { return values[range].map(transform) }
        var result: [Element] = []; result.reserveCapacity(range.count)
        for index in range { try context.charge(.workUnits); result.append(transform(values[index])) }
        return result
    }

    private func encodeAdmitted(_ design: borrowing MappedGateDesign, context: inout LogicKernelContext) throws -> Data {
        let record = try design.withTables { nets, instances, pins, ports, bits, _ in
            var nr: [Net] = []; var ir: [Instance] = []; var pr: [Port] = []
            nr.reserveCapacity(nets.count); ir.reserveCapacity(instances.count); pr.reserveCapacity(ports.count)
            for n in nets.indices {
                try context.charge(.workUnits)
                let value = nets[n]; let driver: Driver
                switch value.driver {
                case .input: driver = .input
                case .constant(let v): driver = .constant(v)
                case .instanceOutput(let i, let p): driver = .output(i.rawValue, p.rawValue)
                }
                nr.append(.init(id: value.id, driver: driver, origin: value.origin.map(Origin.init)))
            }
            for i in instances.indices {
                try context.charge(.workUnits)
                let value = instances[i]; let cell = try design.library.cell(at: value.cell)
                var connections: [Int] = []; var names: [String] = []
                connections.reserveCapacity(cell.pinCount); names.reserveCapacity(cell.pinCount)
                for p in 0..<cell.pinCount {
                    try context.charge(.workUnits)
                    names.append(try cell.pin(at: .init(p)).name)
                    connections.append(pins[value.pins.lowerBound + p].rawValue)
                }
                ir.append(.init(id: value.id, cellID: cell.id, cellName: cell.name,
                    pinNames: names, nets: connections, stateID: value.stateID,
                    initial: value.initialValue, origin: value.origin.map(Origin.init)))
            }
            for p in ports.indices {
                try context.charge(.workUnits)
                let value = ports[p]; var connections: [Int] = []
                connections.reserveCapacity(value.bits.count)
                for b in value.bits { try context.charge(.workUnits); connections.append(bits[b].rawValue) }
                pr.append(.init(id: value.id, input: value.direction == .input, nets: connections))
            }
            return Record(schemaVersion: 1, representation: "mapped-gates", library: design.library.source,
                          nets: nr, instances: ir, ports: pr)
        }
        let count = try encodedSize(record, context: &context)
        try context.charge(.outputBytes, amount: UInt64(count))
        _ = try LogicGraphJSONSize.reserve(try LogicGraphJSONPreflight.add(count, MemoryLayout<Data>.stride), context: &context)
        try context.checkpoint()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        try context.checkpoint()
        guard data.count <= count else { throw LogicKernelError.invalidModel("Controlled JSON exceeds its schema-derived escape bound") }
        return data
    }

    public func decode(_ data: Data, library: borrowing LogicTechnologyLibrary,
                       context: inout LogicKernelContext) throws -> MappedGateDesign {
        try decodeAdmitted(data, library: library, context: &context, controlled: false)
    }

    private func decodeAdmitted(_ data: Data, library: borrowing LogicTechnologyLibrary,
                       context: inout LogicKernelContext, controlled: Bool) throws -> MappedGateDesign {
        if !controlled { try context.charge(.expansion, amount: UInt64(data.count)) }
        let record = try JSONDecoder().decode(Record.self, from: data)
        if controlled { try context.checkpoint() }
        guard record.schemaVersion == 1, record.representation == "mapped-gates",
              record.library == library.source else {
            throw LogicKernelError.invalidInput("Mapped schema or exact library source differs")
        }
        var cells: [DesignEntityID: Int] = [:]
        try library.withCells { values in
            for c in values.indices {
                if controlled { try context.charge(.workUnits) }
                guard cells.updateValue(c, forKey: values[c].id) == nil else {
                    throw LogicKernelError.invalidModel("Duplicate library cell identity")
                }
            }
        }
        var pinCount = 0; var bitCount = 0
        for instance in record.instances { if controlled { try context.charge(.workUnits) }; pinCount = try sum(pinCount, instance.nets.count) }
        for port in record.ports { if controlled { try context.charge(.workUnits) }; bitCount = try sum(bitCount, port.nets.count) }
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
                if controlled { try context.charge(.workUnits) }
                guard instance.pinNames[p] == (try cell.pin(at: .init(p)).name) else {
                    throw LogicKernelError.invalidModel("Physical pin identity differs")
                }
            }
            _ = try builder.addInstance(id: instance.id, cell: .init(index),
                pinNets: try indices(instance.nets, range: instance.nets.indices, controlled: controlled, context: &context, transform: MappedNetIndex.init), stateID: instance.stateID,
                initialValue: instance.initial, origin: try instance.origin?.value(), context: &context)
        }
        for port in record.ports {
            try builder.addPort(id: port.id, direction: port.input ? .input : .output,
                                nets: try indices(port.nets, range: port.nets.indices, controlled: controlled, context: &context, transform: MappedNetIndex.init), context: &context)
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
