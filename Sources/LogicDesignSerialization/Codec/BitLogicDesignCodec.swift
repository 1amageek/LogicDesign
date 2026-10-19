import Foundation
import CircuiteFoundationFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public struct BitLogicDesignCodec: BitLogicDesignCoding {
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

    public func decode(_ data: Data, context: inout LogicKernelContext) throws -> BitLogicDesign {
        try context.charge(.expansion, amount: UInt64(data.count))
        let record = try JSONDecoder().decode(Record.self, from: data)
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
            let inputs = record.operands[range].map(BitNodeIndex.init)
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
                                bits: record.portBits[range].map(BitNodeIndex.init), context: &context)
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
