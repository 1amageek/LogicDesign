import Foundation
import LogicKernelCore

/// Private schema-v1 lexical admission, not a general JSON object model.
internal enum LogicGraphJSONPreflight {
    enum Schema { case bit, mapped }
    struct Counts {
        var nodes = 0; var operands = 0; var ports = 0; var bits = 0; var states = 0
        var nets = 0; var instances = 0; var pinNames = 0; var connections = 0
        var strings = 0; var stringBytes = 0
        var identifiers = 0; var identifierBytes = 0; var artifacts = 0; var artifactHexBytes = 0
    }
    private enum Role {
        case bit, mapped, bitNode, bitPort, bitState, mappedNet, instance, mappedPort
        case nodeArray, operandArray, bitPortArray, bitArray, stateArray
        case netArray, instanceArray, mappedPortArray, namesArray, connectionArray
        case owned, origin, identifier, artifact, ignored
        var element: Role {
            switch self {
            case .nodeArray: .bitNode
            case .bitPortArray: .bitPort
            case .stateArray: .bitState
            case .netArray: .mappedNet
            case .instanceArray: .instance
            case .mappedPortArray: .mappedPort
            case .operandArray, .bitArray, .namesArray, .connectionArray: .owned
            default: .ignored
            }
        }
    }
    private struct Key {
        var bytes = SIMD32<UInt8>(repeating: 0)
        var count = 0
        var ascii = true
        mutating func append(_ value: UInt32) {
            if value > 127 || count >= 32 { ascii = false }
            if count < 32, value <= 127 { bytes[count] = UInt8(value) }
            count += 1
        }
        func equals(_ value: StaticString) -> Bool {
            guard ascii, value.utf8CodeUnitCount == count else { return false }
            return value.withUTF8Buffer { expected in
                for i in expected.indices where expected[i] != bytes[i] { return false }
                return true
            }
        }
    }
    private struct Frame {
        let role: Role
        let object: Bool
        let objectID: Int
        let keyStart: Int
        var state: UInt8 = 0
        var valueRole: Role = .ignored
    }
    private struct KeyRecord {
        let objectID: Int
        let name: String
    }
    // The caller's Data owns this storage for inspect's entire synchronous
    // withUnsafeBytes closure. No Input, pointer, or byte view is returned or stored.
    // unit() checks every bound; this type never allocates or deallocates the borrow.
    private struct Input {
        let bytes: UnsafeBufferPointer<UInt8>
        var offset = 0
        init(_ bytes: UnsafeBufferPointer<UInt8>) {
            self.bytes = bytes
            // Controlled canonical artifacts are UTF-8; legacy Foundation codecs
            // continue to accept their original encoding set.
            if bytes.count >= 3, bytes[0] == 239 && bytes[1] == 187 && bytes[2] == 191 { offset = 3 }
        }
        mutating func unit() throws -> UInt32 {
            guard offset < bytes.count else { throw LogicGraphJSONPreflight.invalid() }
            let result = UInt32(bytes[offset]); offset += 1; return result
        }
        mutating func scalar() throws -> UInt32 {
            let first = try unit()
            if first < 128 { return first }
            let length: Int; let minimum: UInt32; var result: UInt32
            switch first {
            case 0xc2...0xdf: length = 2; minimum = 0x80; result = first & 31
            case 0xe0...0xef: length = 3; minimum = 0x800; result = first & 15
            case 0xf0...0xf4: length = 4; minimum = 0x10000; result = first & 7
            default: throw LogicGraphJSONPreflight.invalid()
            }
            for _ in 1..<length {
                let next = try unit(); guard (128...191).contains(next) else { throw LogicGraphJSONPreflight.invalid() }
                result = result * 64 + (next & 63)
            }
            guard result >= minimum, result <= 0x10ffff, !(0xd800...0xdfff).contains(result) else { throw LogicGraphJSONPreflight.invalid() }
            return result
        }
        mutating func peek() throws -> UInt32? {
            if offset == bytes.count { return nil }
            let saved = offset; let value = try scalar(); offset = saved; return value
        }
        mutating func whitespace(context: inout LogicKernelContext) throws {
            while let value = try peek(), value == 32 || value == 9 || value == 10 || value == 13 { try context.charge(.workUnits); _ = try scalar() }
        }
        mutating func string(context: inout LogicKernelContext, emit: (UInt32) throws -> Void = { _ in }) throws -> (key: Key, bytes: Int) {
            guard try scalar() == 34 else { throw LogicGraphJSONPreflight.invalid() }
            var key = Key(); var count = 0
            while true {
                try context.charge(.workUnits)
                var value = try scalar()
                if value == 34 { return (key, count) }
                guard value >= 32 else { throw LogicGraphJSONPreflight.invalid() }
                if value == 92 {
                    value = try scalar()
                    switch value {
                    case 34, 47, 92: break
                    case 98: value = 8
                    case 102: value = 12
                    case 110: value = 10
                    case 114: value = 13
                    case 116: value = 9
                    case 117:
                        value = try hex4()
                        if (0xd800...0xdbff).contains(value) {
                            guard try scalar() == 92, try scalar() == 117 else { throw LogicGraphJSONPreflight.invalid() }
                            let low = try hex4(); guard (0xdc00...0xdfff).contains(low) else { throw LogicGraphJSONPreflight.invalid() }
                            value = 0x10000 + (value - 0xd800) * 1024 + low - 0xdc00
                        } else if (0xdc00...0xdfff).contains(value) { throw LogicGraphJSONPreflight.invalid() }
                    default: throw LogicGraphJSONPreflight.invalid()
                    }
                }
                try emit(value)
                key.append(value)
                count = try LogicGraphJSONPreflight.add(count, value < 128 ? 1 : value < 2048 ? 2 : value < 65536 ? 3 : 4)
            }
        }
        mutating func keyString(start: Int, length: Int, context: inout LogicKernelContext) throws -> String {
            offset = start
            var decoded: [UInt8] = []; decoded.reserveCapacity(length)
            _ = try string(context: &context) { scalar in
                // Scalar validity was established by the first scan; UTF-8 needs
                // exactly this many bytes, including escaped surrogate pairs.
                if scalar < 128 { decoded.append(UInt8(scalar)) }
                else if scalar < 2048 {
                    decoded.append(UInt8(0xc0 | (scalar >> 6))); decoded.append(UInt8(0x80 | (scalar & 63)))
                } else if scalar < 65536 {
                    decoded.append(UInt8(0xe0 | (scalar >> 12))); decoded.append(UInt8(0x80 | ((scalar >> 6) & 63)))
                    decoded.append(UInt8(0x80 | (scalar & 63)))
                } else {
                    decoded.append(UInt8(0xf0 | (scalar >> 18))); decoded.append(UInt8(0x80 | ((scalar >> 12) & 63)))
                    decoded.append(UInt8(0x80 | ((scalar >> 6) & 63))); decoded.append(UInt8(0x80 | (scalar & 63)))
                }
            }
            return String(decoding: decoded, as: UTF8.self)
        }
        mutating func hex4() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                let scalar = try scalar(); let digit: UInt32
                switch scalar {
                case 48...57: digit = scalar - 48
                case 65...70: digit = scalar - 55
                case 97...102: digit = scalar - 87
                default: throw LogicGraphJSONPreflight.invalid()
                }
                value = value * 16 + digit
            }
            return value
        }
        mutating func literal(_ value: StaticString) throws {
            // StaticString's scoped UTF-8 callback is nonthrowing. Preserve the
            // first parser/control error and rethrow after that borrow ends.
            let failure: (any Error)? = value.withUTF8Buffer { bytes in
                do {
                    for byte in bytes {
                        guard try scalar() == UInt32(byte) else { throw LogicGraphJSONPreflight.invalid() }
                    }
                    return nil
                } catch { return error }
            }
            if let failure { throw failure }
        }
        mutating func number(context: inout LogicKernelContext) throws {
            if try peek() == 45 { _ = try scalar() }
            guard let initial = try peek(), (48...57).contains(initial) else { throw LogicGraphJSONPreflight.invalid() }
            _ = try scalar()
            if initial != 48 { while let next = try peek(), (48...57).contains(next) { try context.charge(.workUnits); _ = try scalar() } }
            if try peek() == 46 {
                _ = try scalar(); try digits(context: &context)
            }
            if let next = try peek(), next == 69 || next == 101 {
                _ = try scalar()
                if let sign = try peek(), sign == 43 || sign == 45 { _ = try scalar() }
                try digits(context: &context)
            }
        }
        mutating func digits(context: inout LogicKernelContext) throws {
            var found = false
            while let next = try peek(), (48...57).contains(next) { try context.charge(.workUnits); found = true; _ = try scalar() }
            guard found else { throw LogicGraphJSONPreflight.invalid() }
        }
    }
    static func inspect(_ data: Data, schema: Schema, context: inout LogicKernelContext) throws -> Counts {
        try context.charge(.expansion, amount: UInt64(data.count))
        // Two bounded passes: the first derives exact explicit stack capacity.
        try context.charge(.workUnits, amount: UInt64(data.count))
        return try data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var probe = Input(bytes); var depth = 0; var maximum = 0; var possibleKeys = 0; var possibleKeyBytes = 0
            while let value = try probe.peek() {
                try context.checkpoint()
                if value == 34 {
                    let string = try probe.string(context: &context)
                    possibleKeys = try LogicGraphJSONPreflight.add(possibleKeys, 1)
                    possibleKeyBytes = try LogicGraphJSONPreflight.add(possibleKeyBytes, string.bytes)
                    continue
                }
                _ = try probe.scalar()
                if value == 91 || value == 123 { depth = try LogicGraphJSONPreflight.add(depth, 1); maximum = max(maximum, depth) }
                if value == 93 || value == 125 { depth -= 1; guard depth >= 0 else { throw LogicGraphJSONPreflight.invalid() } }
            }
            guard depth == 0 else { throw LogicGraphJSONPreflight.invalid() }
            var offer = LogicGraphJSONSize()
            try offer.array(maximum, of: Frame.self)
            try offer.array(possibleKeys, of: KeyRecord.self)
            // Every key is a source string token. Include its decoding byte array
            // plus resulting String while both coexist, before either is built.
            try offer.add(try LogicGraphJSONPreflight.multiply(possibleKeyBytes, 2))
            try offer.add(MemoryLayout<[UInt8]>.stride + MemoryLayout<String>.stride)
            let stackBytes = offer.value
            let receipt = try context.reserveStorage(byteCount: UInt64(stackBytes))
            let result: Counts
            do {
                var stack: [Frame] = []; stack.reserveCapacity(maximum)
                var keys: [KeyRecord] = []; keys.reserveCapacity(possibleKeys)
                var input = Input(bytes); var counts = Counts(); var rootDone = false
                while true {
                    try context.charge(.workUnits)
                    try input.whitespace(context: &context)
                    if stack.isEmpty {
                        if rootDone { guard try input.peek() == nil else { throw LogicGraphJSONPreflight.invalid() }; break }
                        rootDone = true
                        try value(&input, role: schema == .bit ? .bit : .mapped, stack: &stack, counts: &counts, context: &context, keyCount: keys.count)
                        continue
                    }
                    let i = stack.count - 1
                    if stack[i].object {
                        switch stack[i].state {
                        case 0, 4:
                            if try input.peek() == 125 {
                                guard stack[i].state == 0 else { throw LogicGraphJSONPreflight.invalid() }
                                _ = try input.scalar()
                                try context.charge(.workUnits, amount: UInt64(keys.count - stack[i].keyStart))
                                keys.removeSubrange(stack[i].keyStart..<keys.count)
                                stack.removeLast(); continue
                            }
                            let start = input.offset
                            let key = try input.string(context: &context)
                            let end = input.offset
                            let name = try input.keyString(start: start, length: key.bytes, context: &context)
                            input.offset = end
                            for keyIndex in stack[i].keyStart..<keys.count {
                                try context.charge(.workUnits)
                                let previous = keys[keyIndex]
                                if previous.objectID != stack[i].objectID { continue }
                                try context.charge(.workUnits, amount: UInt64(try LogicGraphJSONPreflight.add(previous.name.utf8.count, name.utf8.count)))
                                guard previous.name != name else { throw LogicKernelError.invalidInput("Duplicate controlled graph JSON key") }
                            }
                            keys.append(KeyRecord(objectID: stack[i].objectID, name: name))
                            stack[i].valueRole = child(stack[i].role, key.key)
                            stack[i].state = 1
                        case 1:
                            guard try input.scalar() == 58 else { throw LogicGraphJSONPreflight.invalid() }; stack[i].state = 2
                        case 2:
                            let role = stack[i].valueRole; stack[i].state = 3
                            try value(&input, role: role, stack: &stack, counts: &counts, context: &context, keyCount: keys.count)
                        default:
                            let separator = try input.scalar()
                            if separator == 125 {
                                try context.charge(.workUnits, amount: UInt64(keys.count - stack[i].keyStart))
                                keys.removeSubrange(stack[i].keyStart..<keys.count)
                                stack.removeLast()
                            }
                            else if separator == 44 { stack[i].state = 4 }
                            else { throw LogicGraphJSONPreflight.invalid() }
                        }
                    } else {
                        switch stack[i].state {
                        case 0, 2:
                            if try input.peek() == 93 {
                                guard stack[i].state == 0 else { throw LogicGraphJSONPreflight.invalid() }
                                _ = try input.scalar()
                                try context.charge(.workUnits, amount: UInt64(keys.count - stack[i].keyStart))
                                keys.removeSubrange(stack[i].keyStart..<keys.count)
                                stack.removeLast(); continue
                            }
                            let role = stack[i].role
                            try countElement(role, counts: &counts)
                            stack[i].state = 1
                            try value(&input, role: role.element, stack: &stack, counts: &counts, context: &context, keyCount: keys.count)
                        default:
                            let separator = try input.scalar()
                            if separator == 93 {
                                try context.charge(.workUnits, amount: UInt64(keys.count - stack[i].keyStart))
                                keys.removeSubrange(stack[i].keyStart..<keys.count)
                                stack.removeLast()
                            }
                            else if separator == 44 { stack[i].state = 2 }
                            else { throw LogicGraphJSONPreflight.invalid() }
                        }
                    }
                }
                // Drop the stack before refunding its admitted logical payload.
                stack = []; keys = []
                result = counts
            } catch {
                try context.releaseStorage(receipt)
                throw error
            }
            // Consume once on each exit. A release failure must never re-enter
            // the parsing catch with an already-consumed reservation.
            try context.releaseStorage(receipt)
            return result
        }
    }
    private static func value(_ input: inout Input, role: Role, stack: inout [Frame], counts: inout Counts, context: inout LogicKernelContext, keyCount: Int) throws {
        guard let first = try input.peek() else { throw LogicGraphJSONPreflight.invalid() }
        switch first {
        case 123, 91:
            _ = try input.scalar()
            stack.append(Frame(role: role, object: first == 123, objectID: input.offset, keyStart: keyCount))
        case 34:
            let value = try input.string(context: &context)
            if role != .ignored {
                counts.strings = try LogicGraphJSONPreflight.add(counts.strings, 1)
                counts.stringBytes = try LogicGraphJSONPreflight.add(counts.stringBytes, value.bytes)
                if role == .identifier {
                    counts.identifiers = try LogicGraphJSONPreflight.add(counts.identifiers, 1)
                    counts.identifierBytes = try LogicGraphJSONPreflight.add(counts.identifierBytes, value.bytes)
                }
                if role == .artifact {
                    counts.artifacts = try LogicGraphJSONPreflight.add(counts.artifacts, 1)
                    counts.artifactHexBytes = try LogicGraphJSONPreflight.add(counts.artifactHexBytes, value.bytes)
                }
            }
        case 116: try input.literal("true")
        case 102: try input.literal("false")
        case 110: try input.literal("null")
        case 45, 48...57: try input.number(context: &context)
        default: throw LogicGraphJSONPreflight.invalid()
        }
    }
    private static func child(_ role: Role, _ key: Key) -> Role {
        switch role {
        case .bit:
            if key.equals("nodes") { return .nodeArray }
            if key.equals("operands") { return .operandArray }
            if key.equals("ports") { return .bitPortArray }
            if key.equals("portBits") { return .bitArray }
            if key.equals("states") { return .stateArray }
        case .mapped:
            if key.equals("nets") { return .netArray }
            if key.equals("instances") { return .instanceArray }
            if key.equals("ports") { return .mappedPortArray }
            if key.equals("representation") { return .owned }
            if key.equals("library") { return .artifact }
        case .instance:
            if key.equals("pinNames") { return .namesArray }
            if key.equals("nets") { return .connectionArray }
            if key.equals("id") || key.equals("cellID") || key.equals("stateID") { return .identifier }
            if key.equals("cellName") { return .owned }
            if key.equals("origin") { return .origin }
        case .mappedPort:
            if key.equals("nets") { return .connectionArray }
            if key.equals("id") { return .identifier }
        case .bitNode, .bitState:
            if key.equals("id") { return .identifier }
            if key.equals("origin") { return .origin }
        case .bitPort:
            if key.equals("direction") { return .owned }
            if key.equals("id") { return .identifier }
        case .mappedNet:
            if key.equals("id") { return .identifier }
            if key.equals("origin") { return .origin }
        case .origin:
            if key.equals("artifact") || key.equals("artifactID") { return .artifact }
        case .owned: return .owned
        default: break
        }
        return .ignored
    }
    private static func countElement(_ role: Role, counts: inout Counts) throws {
        switch role {
        case .nodeArray: counts.nodes = try LogicGraphJSONPreflight.add(counts.nodes, 1)
        case .operandArray: counts.operands = try LogicGraphJSONPreflight.add(counts.operands, 1)
        case .bitPortArray, .mappedPortArray: counts.ports = try LogicGraphJSONPreflight.add(counts.ports, 1)
        case .bitArray: counts.bits = try LogicGraphJSONPreflight.add(counts.bits, 1)
        case .stateArray: counts.states = try LogicGraphJSONPreflight.add(counts.states, 1)
        case .netArray: counts.nets = try LogicGraphJSONPreflight.add(counts.nets, 1)
        case .instanceArray: counts.instances = try LogicGraphJSONPreflight.add(counts.instances, 1)
        case .namesArray: counts.pinNames = try LogicGraphJSONPreflight.add(counts.pinNames, 1)
        case .connectionArray: counts.connections = try LogicGraphJSONPreflight.add(counts.connections, 1)
        default: break
        }
    }
    static func add(_ a: Int, _ b: Int) throws -> Int {
        let result = a.addingReportingOverflow(b)
        guard !result.overflow, result.partialValue >= 0 else { throw LogicGraphJSONPreflight.invalid() }
        return result.partialValue
    }
    static func multiply(_ a: Int, _ b: Int) throws -> Int {
        let result = a.multipliedReportingOverflow(by: b)
        guard !result.overflow, result.partialValue >= 0 else { throw LogicGraphJSONPreflight.invalid() }
        return result.partialValue
    }
    private static func invalid() -> LogicKernelError { .invalidInput("Malformed, non-UTF-8 or oversized controlled graph JSON") }
}
