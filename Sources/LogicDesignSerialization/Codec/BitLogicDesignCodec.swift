import Foundation
import CircuiteFoundationFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public struct BitLogicDesignCodec: BitLogicDesignControlledCoding {
    public init() {}

    public func encode(_ design: borrowing BitLogicDesign) throws -> Data {
        let record = design.withTables { nodes, operands, ports, bits, states, _ in
            var nodeRecords: [NodeRecord] = []; nodeRecords.reserveCapacity(nodes.count)
            var operandRecords: [Int] = []; operandRecords.reserveCapacity(operands.count)
            var portRecords: [PortRecord] = []; portRecords.reserveCapacity(ports.count)
            var bitRecords: [Int] = []; bitRecords.reserveCapacity(bits.count)
            var stateRecords: [StateRecord] = []; stateRecords.reserveCapacity(states.count)
            for index in nodes.indices {
                let node = nodes[index]
                nodeRecords.append(NodeRecord(id: node.id, operation: OperationRecord(node.operation),
                    operandStart: node.operands.lowerBound, operandCount: node.operands.count,
                    origin: node.origin.map(OriginRecord.init)))
            }
            for index in operands.indices { operandRecords.append(operands[index].rawValue) }
            for index in ports.indices {
                let port = ports[index]
                portRecords.append(PortRecord(id: port.id, direction: port.direction == .input ? .input : .output,
                    bitStart: port.bits.lowerBound, bitCount: port.bits.count))
            }
            for index in bits.indices { bitRecords.append(bits[index].rawValue) }
            for index in states.indices { stateRecords.append(StateRecord(states[index])) }
            return Record(schemaVersion: 1, nodes: nodeRecords, operands: operandRecords,
                          ports: portRecords, portBits: bitRecords, states: stateRecords)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(record)
    }

    // Keep the returned retention anchor with the value and all escaped copies.
    public func encodeControlled(_ design: borrowing BitLogicDesign, context: inout LogicKernelContext)
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
    public func decodeControlled(_ data: Data, context: inout LogicKernelContext)
        throws -> (value: BitLogicDesign, retention: LogicKernelRetention) {
        let scope = try context.beginRetentionScope()
        do {
            let failureMetadata = try context.reserveStorage(byteCount: UInt64(MemoryLayout<LogicGraphCodecSourceFailure>.stride))
            let counts = try LogicGraphJSONPreflight.inspect(data, schema: .bit, context: &context)
            var bytes = LogicGraphJSONSize()
            try bytes.add(try decodingWorkspace(counts))
            let conversion = try LogicGraphJSONSize.decodedStrings(counts)
            try bytes.add(conversion)
            try context.charge(.workUnits, amount: UInt64(conversion))
            let temporary = try LogicGraphJSONSize.reserve(bytes.value, context: &context)
            _ = try LogicGraphJSONSize.reserve(try LogicGraphJSONSize.decodedArtifactBacking(counts), context: &context)
            let value = try decodeAdmitted(data, context: &context, controlled: true)
            try context.releaseStorage(temporary)
            try context.releaseStorage(failureMetadata)
            return (value, try context.finishRetentionScope(scope))
        } catch {
            try LogicGraphCodecSourceFailure.rethrow(error, scope: scope, context: &context)
        }
    }

    private func decodingWorkspace(_ counts: LogicGraphJSONPreflight.Counts) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(MemoryLayout<Record>.stride)
        try size.array(counts.nodes, of: NodeRecord.self)
        try size.array(counts.operands, of: Int.self)
        try size.array(counts.ports, of: PortRecord.self)
        try size.array(counts.bits, of: Int.self)
        try size.array(counts.states, of: StateRecord.self)
        // All per-row index materializations are bounded by their disjoint flat tables.
        try size.array(counts.operands, of: BitNodeIndex.self)
        try size.array(counts.bits, of: BitNodeIndex.self)
        try size.add(2 * MemoryLayout<[BitNodeIndex]>.stride)
        return size.value
    }
    private func encodingWorkspace(_ design: borrowing BitLogicDesign, context: inout LogicKernelContext) throws -> Int {
        try design.withTables { nodes, operands, ports, bits, states, _ in
            var size = LogicGraphJSONSize(); try size.add(MemoryLayout<Record>.stride)
            try size.array(nodes.count, of: NodeRecord.self); try size.array(operands.count, of: Int.self)
            try size.array(ports.count, of: PortRecord.self); try size.array(bits.count, of: Int.self)
            try size.array(states.count, of: StateRecord.self)
            let ids = try LogicGraphJSONPreflight.add(try LogicGraphJSONPreflight.add(nodes.count, ports.count), states.count)
            try size.add(try LogicGraphJSONSize.encodedIdentifierScratch(ids))
            for i in nodes.indices {
                try context.charge(.workUnits)
                if let origin = nodes[i].origin { try size.add(try LogicGraphJSONSize.encodedArtifactScratch(origin.artifactID)) }
            }
            for i in states.indices {
                try context.charge(.workUnits)
                if let origin = states[i].origin { try size.add(try LogicGraphJSONSize.encodedArtifactScratch(origin.artifactID)) }
            }
            return size.value
        }
    }
    private func encodedSize(_ record: Record, context: inout LogicKernelContext) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(LogicGraphJSONSize.objectHeader(6))
        var nodes = LogicGraphJSONSize(); try nodes.add(try LogicGraphJSONSize.arrayHeader(record.nodes.count))
        for node in record.nodes {
            try context.charge(.workUnits)
            var row = LogicGraphJSONSize(); try row.add(LogicGraphJSONSize.objectHeader(node.origin == nil ? 4 : 5))
            try row.field("id", 18); try row.field("operandStart", LogicGraphJSONSize.integer(node.operandStart))
            try row.field("operandCount", LogicGraphJSONSize.integer(node.operandCount))
            try row.field("operation", operationSize(node.operation))
            if let origin = node.origin { try row.field("origin", originSize(origin)) }
            try nodes.add(row.value)
        }
        try size.field("nodes", nodes.value)
        try size.field("operands", integerArraySize(record.operands, context: &context))
        try size.field("portBits", integerArraySize(record.portBits, context: &context))
        var ports = LogicGraphJSONSize(); try ports.add(try LogicGraphJSONSize.arrayHeader(record.ports.count))
        for port in record.ports {
            try context.charge(.workUnits)
            var row = LogicGraphJSONSize(); try row.add(LogicGraphJSONSize.objectHeader(4))
            try row.field("id", 18); try row.field("direction", port.direction == .input ? 7 : 8)
            try row.field("bitStart", LogicGraphJSONSize.integer(port.bitStart)); try row.field("bitCount", LogicGraphJSONSize.integer(port.bitCount))
            try ports.add(row.value)
        }
        try size.field("ports", ports.value); try size.field("schemaVersion", 1)
        var states = LogicGraphJSONSize(); try states.add(try LogicGraphJSONSize.arrayHeader(record.states.count))
        for state in record.states {
            try context.charge(.workUnits)
            var row = LogicGraphJSONSize(); try row.add(LogicGraphJSONSize.objectHeader(3 + (state.initialValue == nil ? 0 : 1) + (state.origin == nil ? 0 : 1)))
            try row.field("id", 18); try row.field("next", LogicGraphJSONSize.integer(state.next))
            try row.field("control", controlSize(state.control))
            if let initial = state.initialValue { try row.field("initialValue", LogicGraphJSONSize.boolean(initial)) }
            if let origin = state.origin { try row.field("origin", originSize(origin)) }
            try states.add(row.value)
        }
        try size.field("states", states.value)
        return size.value
    }
    private func integerArraySize(_ values: [Int], context: inout LogicKernelContext) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(try LogicGraphJSONSize.arrayHeader(values.count))
        for value in values { try context.charge(.workUnits); try size.add(LogicGraphJSONSize.integer(value)) }
        return size.value
    }
    private func originSize(_ value: OriginRecord) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(LogicGraphJSONSize.objectHeader(3))
        try size.field("artifactID", LogicGraphJSONSize.artifact(value.artifactID))
        try size.field("start", LogicGraphJSONSize.unsigned(value.start)); try size.field("end", LogicGraphJSONSize.unsigned(value.end))
        return size.value
    }
    private func operationSize(_ operation: OperationRecord) throws -> Int {
        let name: StaticString; let payload: Int
        switch operation {
        case .input: name = "input"; payload = 2
        case .constant(let value):
            name = "constant"; var inner = LogicGraphJSONSize(); try inner.add(2); try inner.field("_0", LogicGraphJSONSize.boolean(value)); payload = inner.value
        case .state(let value):
            name = "state"; var inner = LogicGraphJSONSize(); try inner.add(2); try inner.field("_0", LogicGraphJSONSize.integer(value)); payload = inner.value
        case .buffer: name = "buffer"; payload = 2
        case .invert: name = "invert"; payload = 2
        case .and: name = "and"; payload = 2
        case .or: name = "or"; payload = 2
        case .xor: name = "xor"; payload = 2
        case .select: name = "select"; payload = 2
        }
        var size = LogicGraphJSONSize(); try size.add(2); try size.field(name, payload); return size.value
    }
    private func resetSize(_ reset: ResetRecord) throws -> Int {
        var size = LogicGraphJSONSize(); try size.add(LogicGraphJSONSize.objectHeader(4))
        try size.field("signal", LogicGraphJSONSize.integer(reset.signal))
        try size.field("activeHigh", LogicGraphJSONSize.boolean(reset.activeHigh))
        try size.field("value", LogicGraphJSONSize.boolean(reset.value))
        try size.field("asynchronous", LogicGraphJSONSize.boolean(reset.asynchronous))
        return size.value
    }
    private func controlSize(_ control: ControlRecord) throws -> Int {
        let name: StaticString; var inner = LogicGraphJSONSize()
        switch control {
        case .flipFlop(let clock, let rising, let enable, let reset):
            name = "flipFlop"; try inner.add(LogicGraphJSONSize.objectHeader(2 + (enable == nil ? 0 : 1) + (reset == nil ? 0 : 1)))
            try inner.field("clock", LogicGraphJSONSize.integer(clock)); try inner.field("rising", LogicGraphJSONSize.boolean(rising))
            if let enable { try inner.field("enable", LogicGraphJSONSize.integer(enable)) }
            if let reset { try inner.field("reset", resetSize(reset)) }
        case .latch(let gate, let activeHigh, let reset):
            name = "latch"; try inner.add(LogicGraphJSONSize.objectHeader(2 + (reset == nil ? 0 : 1)))
            try inner.field("gate", LogicGraphJSONSize.integer(gate)); try inner.field("activeHigh", LogicGraphJSONSize.boolean(activeHigh))
            if let reset { try inner.field("reset", resetSize(reset)) }
        }
        var size = LogicGraphJSONSize(); try size.add(2); try size.field(name, inner.value); return size.value
    }

    private func indices<Element>(_ values: [Int], range: Range<Int>, controlled: Bool,
        context: inout LogicKernelContext, transform: (Int) -> Element) throws(LogicKernelError) -> [Element] {
        if !controlled { return values[range].map(transform) }
        var result: [Element] = []; result.reserveCapacity(range.count)
        for index in range { try context.charge(.workUnits); result.append(transform(values[index])) }
        return result
    }

    private func encodeAdmitted(_ design: borrowing BitLogicDesign, context: inout LogicKernelContext) throws -> Data {
        let record = try design.withTables { nodes, operands, ports, bits, states, _ in
            var nodeRecords: [NodeRecord] = []; nodeRecords.reserveCapacity(nodes.count)
            var operandRecords: [Int] = []; operandRecords.reserveCapacity(operands.count)
            var portRecords: [PortRecord] = []; portRecords.reserveCapacity(ports.count)
            var bitRecords: [Int] = []; bitRecords.reserveCapacity(bits.count)
            var stateRecords: [StateRecord] = []; stateRecords.reserveCapacity(states.count)
            for index in nodes.indices {
                try context.charge(.workUnits)
                let node = nodes[index]
                nodeRecords.append(NodeRecord(id: node.id, operation: OperationRecord(node.operation),
                    operandStart: node.operands.lowerBound, operandCount: node.operands.count,
                    origin: node.origin.map(OriginRecord.init)))
            }
            for index in operands.indices { try context.charge(.workUnits); operandRecords.append(operands[index].rawValue) }
            for index in ports.indices {
                try context.charge(.workUnits)
                let port = ports[index]
                portRecords.append(PortRecord(id: port.id, direction: port.direction == .input ? .input : .output,
                    bitStart: port.bits.lowerBound, bitCount: port.bits.count))
            }
            for index in bits.indices { try context.charge(.workUnits); bitRecords.append(bits[index].rawValue) }
            for index in states.indices { try context.charge(.workUnits); stateRecords.append(StateRecord(states[index])) }
            return Record(schemaVersion: 1, nodes: nodeRecords, operands: operandRecords,
                          ports: portRecords, portBits: bitRecords, states: stateRecords)
        }
        let count = try encodedSize(record, context: &context)
        try context.charge(.outputBytes, amount: UInt64(count))
        _ = try LogicGraphJSONSize.reserve(try LogicGraphJSONPreflight.add(count, MemoryLayout<Data>.stride), context: &context)
        try context.checkpoint()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        try context.checkpoint()
        guard data.count <= count else { throw LogicKernelError.invalidModel("Controlled JSON exceeds its schema-derived escape bound") }
        return data
    }

    public func decode(_ data: Data, context: inout LogicKernelContext) throws -> BitLogicDesign {
        try decodeAdmitted(data, context: &context, controlled: false)
    }

    private func decodeAdmitted(_ data: Data, context: inout LogicKernelContext, controlled: Bool) throws -> BitLogicDesign {
        if !controlled { try context.charge(.expansion, amount: UInt64(data.count)) }
        let record = try JSONDecoder().decode(Record.self, from: data)
        if controlled { try context.checkpoint() }
        guard record.schemaVersion == 1 else {
            throw LogicKernelError.unsupported("Unsupported bit graph schema")
        }
        var builder = try BitLogicBuilder(capacity: BitGraphCapacity(nodes: record.nodes.count,
            operands: record.operands.count, ports: record.ports.count,
            portBits: record.portBits.count, states: record.states.count), context: &context)
        var expectedOperand = 0
        for node in record.nodes {
            try context.checkpoint()
            let range = try checkedRange(start: node.operandStart, count: node.operandCount,
                                         limit: record.operands.count, expected: expectedOperand)
            expectedOperand = range.upperBound
            let inputs = try indices(record.operands, range: range, controlled: controlled, context: &context, transform: BitNodeIndex.init)
            _ = try builder.addNode(id: node.id, operation: node.operation.value,
                inputs: inputs, origin: try node.origin?.value(), context: &context)
        }
        guard expectedOperand == record.operands.count else { throw LogicKernelError.invalidModel("Unowned serialized operands") }
        var expectedBit = 0
        for port in record.ports {
            let range = try checkedRange(start: port.bitStart, count: port.bitCount,
                                         limit: record.portBits.count, expected: expectedBit)
            expectedBit = range.upperBound
            try builder.addPort(id: port.id, direction: port.direction == .input ? .input : .output,
                                bits: try indices(record.portBits, range: range, controlled: controlled, context: &context, transform: BitNodeIndex.init), context: &context)
        }
        guard expectedBit == record.portBits.count else { throw LogicKernelError.invalidModel("Unowned serialized port bits") }
        for state in record.states { _ = try builder.addState(state.value(), context: &context) }
        return try builder.finish(context: &context)
    }

    private func checkedRange(start: Int, count: Int, limit: Int, expected: Int) throws -> Range<Int> {
        guard start == expected, count >= 0, start >= 0, start <= limit, count <= limit - start else {
            throw LogicKernelError.invalidModel("Invalid serialized table range")
        }
        return start..<(start + count)
    }

    private struct Record: Codable {
        let schemaVersion: Int
        let nodes: [NodeRecord]
        let operands: [Int]
        let ports: [PortRecord]
        let portBits: [Int]
        let states: [StateRecord]
    }
    private struct NodeRecord: Codable {
        let id: DesignEntityID
        let operation: OperationRecord
        let operandStart: Int
        let operandCount: Int
        let origin: OriginRecord?
    }
    private struct PortRecord: Codable {
        enum Direction: String, Codable { case input, output }
        let id: DesignEntityID
        let direction: Direction
        let bitStart: Int
        let bitCount: Int
    }
    private struct OriginRecord: Codable {
        let artifactID: ArtifactID
        let start: UInt64
        let end: UInt64
        init(_ value: LogicKernelSourceRange) {
            artifactID = value.artifactID; start = value.byteRange.lowerBound; end = value.byteRange.upperBound
        }
        func value() throws -> LogicKernelSourceRange {
            guard start <= end else { throw LogicKernelError.invalidModel("Reversed source range") }
            return try LogicKernelSourceRange(artifactID: artifactID, byteRange: start..<end)
        }
    }
    private enum OperationRecord: Codable {
        case input, constant(Bool), state(Int), buffer, invert, and, or, xor, select
        init(_ operation: BitOperation) {
            switch operation {
            case .input: self = .input
            case .constant(let value): self = .constant(value)
            case .state(let index): self = .state(index.rawValue)
            case .buffer: self = .buffer
            case .invert: self = .invert
            case .and: self = .and
            case .or: self = .or
            case .xor: self = .xor
            case .select: self = .select
            }
        }
        var value: BitOperation {
            switch self {
            case .input: .input
            case .constant(let value): .constant(value)
            case .state(let index): .state(BitStateIndex(index))
            case .buffer: .buffer
            case .invert: .invert
            case .and: .and
            case .or: .or
            case .xor: .xor
            case .select: .select
            }
        }
    }
    private struct ResetRecord: Codable {
        let signal: Int
        let activeHigh: Bool
        let value: Bool
        let asynchronous: Bool
        init(_ reset: BitReset) {
            signal = reset.signal.rawValue; activeHigh = reset.activeHigh
            value = reset.value; asynchronous = reset.kind == .asynchronous
        }
        var definition: BitReset {
            BitReset(signal: BitNodeIndex(signal), activeHigh: activeHigh, value: value,
                     kind: asynchronous ? .asynchronous : .synchronous)
        }
    }
    private enum ControlRecord: Codable {
        case flipFlop(clock: Int, rising: Bool, enable: Int?, reset: ResetRecord?)
        case latch(gate: Int, activeHigh: Bool, reset: ResetRecord?)
        init(_ control: BitStateControl) {
            switch control {
            case .flipFlop(let clock, let edge, let enable, let reset):
                self = .flipFlop(clock: clock.rawValue, rising: edge == .rising,
                                enable: enable?.rawValue, reset: reset.map(ResetRecord.init))
            case .latch(let gate, let activeHigh, let reset):
                self = .latch(gate: gate.rawValue, activeHigh: activeHigh, reset: reset.map(ResetRecord.init))
            }
        }
        var value: BitStateControl {
            switch self {
            case .flipFlop(let clock, let rising, let enable, let reset):
                .flipFlop(clock: BitNodeIndex(clock), edge: rising ? .rising : .falling,
                          enable: enable.map(BitNodeIndex.init), reset: reset?.definition)
            case .latch(let gate, let activeHigh, let reset):
                .latch(gate: BitNodeIndex(gate), activeHigh: activeHigh, reset: reset?.definition)
            }
        }
    }
    private struct StateRecord: Codable {
        let id: DesignEntityID
        let next: Int
        let control: ControlRecord
        let initialValue: Bool?
        let origin: OriginRecord?
        init(_ state: BitLogicState) {
            id = state.id; next = state.next.rawValue; control = ControlRecord(state.control)
            initialValue = state.initialValue; origin = state.origin.map(OriginRecord.init)
        }
        func value() throws -> BitLogicState {
            BitLogicState(id: id, next: BitNodeIndex(next), control: control.value,
                          initialValue: initialValue, origin: try origin?.value())
        }
    }
}
