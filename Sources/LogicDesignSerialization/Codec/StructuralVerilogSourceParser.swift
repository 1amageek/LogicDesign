import Foundation
import LogicKernelCore

/// Call-local admission and alias state; no functional or library authority.
struct StructuralVerilogSourceParser {
    typealias Token = MappedGateVerilogLexer.Token
    typealias Failure = StructuralVerilogSourceError
    struct Net { let token: Token; var wired: Bool; var input: Bool }
    struct Port { let token: Token; let direction: StructuralVerilogSource.Port.Direction; let net: Int }
    struct Pin { let token: Token; let net: Int; let range: Range<Int> }
    struct Instance { let token: Token; let cell: Token; let pins: Range<Int>; let range: Range<Int> }
    struct Assignment { let target: Int; let source: Int?; let constant: Bool?; let range: Range<Int> }

    let tokens: [Token]
    let count: Int
    var cursor = 0
    var nets: [Net] = []
    var ports: [Port] = []
    var pins: [Pin] = []
    var instances: [Instance] = []
    var assignments: [Assignment] = []

    init(tokens: [Token], byteCount: Int) {
        self.tokens = tokens; count = byteCount
        nets.reserveCapacity(tokens.count); ports.reserveCapacity(tokens.count)
        pins.reserveCapacity(tokens.count); instances.reserveCapacity(tokens.count)
        assignments.reserveCapacity(tokens.count)
    }

    static func charge(_ resource: LogicResource, _ amount: UInt64 = 1,
                       context: inout LogicKernelContext) throws(Failure) {
        do { try context.charge(resource, amount: amount) } catch { throw .kernel(error) }
    }
    static func reserve(_ bytes: UInt64, context: inout LogicKernelContext) throws(Failure) -> LogicStorageReservation {
        do { return try context.reserveStorage(byteCount: bytes) } catch { throw .kernel(error) }
    }
    static func release(_ reservation: consuming LogicStorageReservation,
                        context: inout LogicKernelContext) throws(Failure) {
        do { try context.releaseStorage(consume reservation) } catch { throw .kernel(error) }
    }
    static func add(_ a: UInt64, _ b: UInt64) throws(Failure) -> UInt64 {
        let result = a.addingReportingOverflow(b)
        guard !result.overflow else { throw .kernel(.invalidInput("Structural payload size overflows")) }
        return result.partialValue
    }
    static func product(_ a: Int, _ b: Int) throws(Failure) -> UInt64 {
        let result = UInt64(a).multipliedReportingOverflow(by: UInt64(b))
        guard !result.overflow else { throw .kernel(.invalidInput("Structural payload size overflows")) }
        return result.partialValue
    }
    static func tableBytes(_ tokenCount: Int) throws(Failure) -> UInt64 {
        // Each draft table is bounded by tokens; alias scratch uses six Int arrays.
        let stride = MemoryLayout<Net>.stride + MemoryLayout<Port>.stride + MemoryLayout<Pin>.stride
            + MemoryLayout<Instance>.stride + MemoryLayout<Assignment>.stride + 6 * MemoryLayout<Int>.stride
            + MemoryLayout<Bool?>.stride + MemoryLayout<Range<Int>?>.stride + MemoryLayout<Token>.stride
        return try add(product(tokenCount, stride), UInt64(MemoryLayout<Self>.stride))
    }
    var range: Range<Int> { cursor < tokens.count ? tokens[cursor].byteRange : count..<count }
    func isBare(_ value: String) -> Bool {
        cursor < tokens.count && !tokens[cursor].escaped && tokens[cursor].value == value
    }
    mutating func take(context: inout LogicKernelContext) throws(Failure) -> Token {
        try Self.charge(.workUnits, context: &context)
        guard cursor < tokens.count else { throw .malformed(byteRange: range, reason: "Truncated structural source") }
        let result = tokens[cursor]; cursor += 1; return result
    }
    mutating func expect(_ value: String, context: inout LogicKernelContext) throws(Failure) {
        let token = try take(context: &context)
        guard !token.escaped, token.value == value else {
            throw .unsupported(byteRange: token.byteRange, semantic: "Expected flat structural syntax: \(value)")
        }
    }
    func same(_ a: String, _ b: String, context: inout LogicKernelContext) throws(Failure) -> Bool {
        try Self.charge(.workUnits, try Self.add(UInt64(a.utf8.count), UInt64(b.utf8.count) + 1), context: &context)
        return a == b
    }
    enum Role { case escaped, net, port, instance }
    mutating func identifier(_ role: Role, context: inout LogicKernelContext) throws(Failure) -> Token {
        let token = try take(context: &context)
        try Self.charge(.workUnits, UInt64(token.value.utf8.count) + 1, context: &context)
        if token.escaped {
            guard !token.value.isEmpty, token.value.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
                throw .unsupported(byteRange: token.byteRange, semantic: "Identifier is outside the emitted ASCII profile")
            }
            return token
        }
        // Bare names are only the existing codec's exact generated spellings.
        var position = 0, groupDigits = 0, firstDigit: UInt8 = 0, groups = 0
        let prefix: UInt8 = role == .instance ? 105 : role == .port ? 112 : 110
        var valid = role != .escaped
        for byte in token.value.utf8 {
            if position == 0 { valid = valid && byte == prefix }
            else if byte == 95 && role == .port && groups == 0 && groupDigits > 0 {
                valid = valid && (groupDigits == 1 || firstDigit != 48)
                groups += 1; groupDigits = 0
            } else {
                valid = valid && byte >= 48 && byte <= 57
                if groupDigits == 0 { firstDigit = byte }; groupDigits += 1
            }
            position += 1
        }
        valid = valid && groupDigits > 0 && (groupDigits == 1 || firstDigit != 48)
            && (role == .port ? groups == 1 : groups == 0)
        // A generated port is also a declared scalar net reference.
        if !valid && role == .net {
            cursor -= 1
            return try identifier(.port, context: &context)
        }
        guard valid else { throw .unsupported(byteRange: token.byteRange, semantic: "Expected escaped or generated identifier") }
        return token
    }
    func findNet(_ token: Token, context: inout LogicKernelContext) throws(Failure) -> Int? {
        for index in nets.indices {
            if try same(token.value, nets[index].token.value, context: &context) { return index }
        }
        return nil
    }
    func requireNet(_ token: Token, context: inout LogicKernelContext) throws(Failure) -> Int {
        guard let index = try findNet(token, context: &context) else {
            throw .malformed(byteRange: token.byteRange, reason: "Undeclared scalar net")
        }
        return index
    }
    mutating func parse(top: String, context: inout LogicKernelContext) throws(Failure) -> Token {
        try Self.charge(.nodes, context: &context)
        try expect("module", context: &context)
        let module = try identifier(.escaped, context: &context)
        guard try same(module.value, top, context: &context) else {
            throw .malformed(byteRange: module.byteRange, reason: "Requested top differs from source module")
        }
        try expect("(", context: &context)
        var header: [Token] = []
        header.reserveCapacity(tokens.count)
        if !isBare(")") {
            while true {
                let port = try identifier(.port, context: &context)
                guard try findNet(port, context: &context) == nil else {
                    throw .malformed(byteRange: port.byteRange, reason: "Duplicate header port")
                }
                try Self.charge(.nodes, 2, context: &context)
                nets.append(.init(token: port, wired: false, input: false)); header.append(port)
                if !isBare(",") { break }; try expect(",", context: &context)
            }
        }
        try expect(")", context: &context); try expect(";", context: &context)
        for index in header.indices {
            let direction: StructuralVerilogSource.Port.Direction
            if isBare("input") { direction = .input; try expect("input", context: &context) }
            else if isBare("output") { direction = .output; try expect("output", context: &context) }
            else { throw .unsupported(byteRange: range, semantic: "Expected ordered scalar input/output declaration") }
            let token = try identifier(.port, context: &context)
            guard try same(token.value, header[index].value, context: &context) else {
                throw .malformed(byteRange: token.byteRange, reason: "Port declaration differs from header order")
            }
            try expect(";", context: &context)
            nets[index].input = direction == .input
            ports.append(.init(token: token, direction: direction, net: index))
        }
        while isBare("wire") {
            try expect("wire", context: &context)
            let token = try identifier(.net, context: &context)
            if let existing = try findNet(token, context: &context) {
                guard !nets[existing].wired else { throw .malformed(byteRange: token.byteRange, reason: "Duplicate wire declaration") }
                nets[existing].wired = true
            } else {
                try Self.charge(.nodes, context: &context)
                nets.append(.init(token: token, wired: true, input: false))
            }
            try expect(";", context: &context)
        }
        while isBare("assign") {
            let start = range.lowerBound; try expect("assign", context: &context)
            let targetToken = try identifier(.net, context: &context)
            let target = try requireNet(targetToken, context: &context)
            guard !nets[target].input else { throw .malformed(byteRange: targetToken.byteRange, reason: "Top input cannot be assigned") }
            for previous in assignments {
                try Self.charge(.workUnits, context: &context)
                guard previous.target != target else { throw .malformed(byteRange: targetToken.byteRange, reason: "Duplicate assignment target") }
            }
            try expect("=", context: &context)
            let source: Int?, constant: Bool?
            if isBare("1'b0") || isBare("1'b1") {
                let value = try take(context: &context); source = nil; constant = value.value == "1'b1"
            } else {
                source = try requireNet(identifier(.net, context: &context), context: &context); constant = nil
            }
            try expect(";", context: &context)
            try Self.charge(.nodes, context: &context)
            assignments.append(.init(target: target, source: source, constant: constant,
                                     range: start..<tokens[cursor - 1].byteRange.upperBound))
        }
        while !isBare("endmodule") {
            let start = range.lowerBound
            let cell = try identifier(.escaped, context: &context)
            let instance = try identifier(.instance, context: &context)
            guard try findNet(instance, context: &context) == nil else {
                throw .malformed(byteRange: instance.byteRange, reason: "Instance collides with a declared net")
            }
            for previous in instances {
                guard try !same(previous.token.value, instance.value, context: &context) else {
                    throw .malformed(byteRange: instance.byteRange, reason: "Duplicate instance")
                }
            }
            try Self.charge(.nodes, context: &context)
            try expect("(", context: &context)
            let firstPin = pins.count
            repeat {
                try expect(".", context: &context)
                let pin = try identifier(.escaped, context: &context)
                for index in firstPin..<pins.count {
                    guard try !same(pin.value, pins[index].token.value, context: &context) else {
                        throw .malformed(byteRange: pin.byteRange, reason: "Duplicate named pin")
                    }
                }
                try expect("(", context: &context)
                let net = try requireNet(identifier(.net, context: &context), context: &context)
                try expect(")", context: &context)
                try Self.charge(.nodes, context: &context)
                pins.append(.init(token: pin, net: net, range: pin.byteRange.lowerBound..<tokens[cursor - 1].byteRange.upperBound))
                if !isBare(",") { break }; try expect(",", context: &context)
            } while true
            try expect(")", context: &context); try expect(";", context: &context)
            instances.append(.init(token: instance, cell: cell, pins: firstPin..<pins.count,
                                   range: start..<tokens[cursor - 1].byteRange.upperBound))
        }
        try expect("endmodule", context: &context)
        guard cursor == tokens.count else { throw .unsupported(byteRange: range, semantic: "Trailing source syntax or multiple modules") }
        return module
    }

    func finish(module: Token, context: inout LogicKernelContext) throws(Failure) -> StructuralVerilogSource {
        let n = nets.count
        var next = [Int](repeating: -1, count: n)
        var assignmentIndex = [Int](repeating: -1, count: n)
        var state = [Int](repeating: 0, count: n)
        var roots = [Int](repeating: -1, count: n)
        var canonical = [Int](repeating: Int.max, count: n)
        var path: [Int] = []; path.reserveCapacity(n)
        for index in assignments.indices {
            try Self.charge(.workUnits, context: &context)
            let assignment = assignments[index]
            assignmentIndex[assignment.target] = index
            if let source = assignment.source { next[assignment.target] = source }
        }
        for start in nets.indices {
            try Self.charge(.workUnits, context: &context)
            if state[start] == 2 { continue }
            path.removeAll(keepingCapacity: true)
            var current = start
            while state[current] == 0 {
                try Self.charge(.workUnits, context: &context)
                state[current] = 1; path.append(current)
                if next[current] < 0 { break }
                current = next[current]
            }
            if state[current] == 1 && next[current] >= 0 {
                let index = assignmentIndex[current]
                throw .malformed(byteRange: assignments[index].range, reason: "Directed alias cycle")
            }
            let root = state[current] == 2 ? roots[current] : current
            for index in path {
                try Self.charge(.workUnits, context: &context)
                roots[index] = root; state[index] = 2
            }
        }
        var constants = [Bool?](repeating: nil, count: n)
        var constantRanges = [Range<Int>?](repeating: nil, count: n)
        for index in nets.indices {
            try Self.charge(.workUnits, context: &context)
            canonical[roots[index]] = min(canonical[roots[index]], index)
        }
        for assignment in assignments {
            try Self.charge(.workUnits, context: &context)
            if let constant = assignment.constant {
                let root = roots[assignment.target]
                if let previous = constants[root], previous != constant {
                    throw .malformed(byteRange: assignment.range, reason: "Contradictory constants on an alias component")
                }
                constants[root] = constant; constantRanges[root] = assignment.range
            }
        }
        func name(_ index: Int) -> String { nets[canonical[roots[index]]].token.value }
        var stringBytes: UInt64 = 0
        func string(_ value: String, context: inout LogicKernelContext) throws(Failure) {
            try Self.charge(.workUnits, UInt64(value.utf8.count) + 1, context: &context)
            stringBytes = try Self.add(stringBytes, UInt64(value.utf8.count))
        }
        try string(module.value, context: &context)
        for port in ports { try string(port.token.value, context: &context); try string(name(port.net), context: &context) }
        for index in nets.indices {
            try string(nets[index].token.value, context: &context); try string(name(index), context: &context)
        }
        for instance in instances {
            try string(instance.token.value, context: &context); try string(instance.cell.value, context: &context)
        }
        for pin in pins {
            try string(pin.token.value, context: &context); try string(nets[pin.net].token.value, context: &context)
            try string(name(pin.net), context: &context)
        }
        var aliasCount = 0
        for assignment in assignments {
            try Self.charge(.workUnits, context: &context)
            if let source = assignment.source {
                aliasCount += 1
                try string(nets[assignment.target].token.value, context: &context)
                try string(nets[source].token.value, context: &context)
            }
        }
        var bytes = try Self.add(stringBytes, UInt64(MemoryLayout<StructuralVerilogSource>.stride))
        for (count, stride) in [
            (ports.count, MemoryLayout<StructuralVerilogSource.Port>.stride),
            (nets.count, MemoryLayout<StructuralVerilogSource.Net>.stride),
            (instances.count, MemoryLayout<StructuralVerilogSource.Instance>.stride),
            (pins.count, MemoryLayout<StructuralVerilogSource.PinConnection>.stride),
            (aliasCount, MemoryLayout<StructuralVerilogSource.Alias>.stride)
        ] { bytes = try Self.add(bytes, Self.product(count, stride)) }
        try Self.charge(.outputBytes, stringBytes, context: &context)
        let retained = try Self.reserve(bytes, context: &context)
        let result: StructuralVerilogSource
        do throws(Failure) {
            var outputPorts: [StructuralVerilogSource.Port] = []; outputPorts.reserveCapacity(ports.count)
            var outputNets: [StructuralVerilogSource.Net] = []; outputNets.reserveCapacity(nets.count)
            var outputInstances: [StructuralVerilogSource.Instance] = []; outputInstances.reserveCapacity(instances.count)
            var outputAliases: [StructuralVerilogSource.Alias] = []; outputAliases.reserveCapacity(aliasCount)
            for port in ports {
                try Self.charge(.workUnits, context: &context)
                outputPorts.append(.init(name: port.token.value, direction: port.direction,
                    netName: name(port.net), byteRange: port.token.byteRange))
            }
            for index in nets.indices {
                try Self.charge(.workUnits, context: &context)
                outputNets.append(.init(name: nets[index].token.value, canonicalName: name(index),
                    constant: constants[roots[index]], constantByteRange: constantRanges[roots[index]],
                    byteRange: nets[index].token.byteRange))
            }
            for instance in instances {
                try Self.charge(.workUnits, context: &context)
                var connections: [StructuralVerilogSource.PinConnection] = []; connections.reserveCapacity(instance.pins.count)
                for index in instance.pins {
                    try Self.charge(.workUnits, context: &context)
                    let pin = pins[index]
                    connections.append(.init(pinName: pin.token.value, netName: nets[pin.net].token.value,
                        canonicalNetName: name(pin.net), byteRange: pin.range))
                }
                outputInstances.append(.init(name: instance.token.value, cellName: instance.cell.value,
                    connections: connections, byteRange: instance.range))
            }
            for assignment in assignments {
                try Self.charge(.workUnits, context: &context)
                if let source = assignment.source {
                    outputAliases.append(.init(target: nets[assignment.target].token.value,
                        source: nets[source].token.value, byteRange: assignment.range))
                }
            }
            result = .init(top: module.value, byteRange: 0..<count, ports: outputPorts, nets: outputNets,
                instances: outputInstances, aliases: outputAliases)
        } catch {
            try Self.release(consume retained, context: &context); throw error
        }
        // The DTO's logical payload remains charged to the caller's cumulative context.
        _ = consume retained
        return result
    }
}
