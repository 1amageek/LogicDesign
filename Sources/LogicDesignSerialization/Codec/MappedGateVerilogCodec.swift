import CircuiteFoundation
import Foundation
import LogicIR
import LogicKernelCore

/// Flat scalar structural Verilog; the sidecar supplies identity, never connectivity or startup.
@available(macOS 26.0, *)
public struct MappedGateVerilogCodec: MappedGateVerilogCoding {
    public init() {}

    public func encode(_ design: borrowing MappedGateDesign, top: String) throws -> Data {
        var text = ""
        try render(design, top: top, names: Names()) { emission in
            if case .text(let fragment) = emission { text += fragment }
        }
        return Data(text.utf8)
    }

    public func encode(_ design: borrowing MappedGateDesign, top: String,
                       naming: borrowing MappedGateVerilogNaming,
                       context: inout LogicKernelContext) throws -> Data {
        try validate(design, top: top, naming: naming, context: &context)
        let names = Names(naming: copy naming)
        var count: UInt64 = 0
        try render(design, top: top, names: names) { emission in
            try account(emission, context: &context)
            if case .text(let fragment) = emission {
                let sum = count.addingReportingOverflow(UInt64(fragment.utf8.count))
                guard !sum.overflow else { throw LogicKernelError.invalidInput("Verilog output size overflows") }
                count = sum.partialValue
            }
        }
        guard let capacity = Int(exactly: count) else { throw LogicKernelError.invalidInput("Verilog output size is not representable") }
        try context.charge(.outputBytes, amount: count)
        let retained = try context.reserveStorage(byteCount: try adding(count, UInt64(MemoryLayout<Data>.stride)))
        let scratch: LogicStorageReservation
        do { scratch = try context.reserveStorage(byteCount: try adding(count, UInt64(MemoryLayout<String>.stride))) }
        catch { try context.releaseStorage(retained); throw error }
        let output: Data
        do {
            var text = ""; text.reserveCapacity(capacity)
            try render(design, top: top, names: names) { emission in
                try account(emission, context: &context)
                if case .text(let fragment) = emission { text += fragment }
            }
            guard text.utf8.count == capacity else { throw LogicKernelError.invalidModel("Verilog preflight and emission differ") }
            output = Data(text.utf8)
        } catch {
            try context.releaseStorage(scratch); try context.releaseStorage(retained); throw error
        }
        try context.releaseStorage(scratch)
        // The returned byte owner's payload stays charged to the invocation.
        _ = consume retained
        return output
    }

    public func decode(_ data: Data, identities: borrowing MappedGateDesign, top: String,
                       context: inout LogicKernelContext) throws -> MappedGateDesign {
        try decodeBody(data, identities: identities, top: top, names: Names(), context: &context)
    }

    public func decode(_ data: Data, identities: borrowing MappedGateDesign, top: String,
                       naming: borrowing MappedGateVerilogNaming,
                       context: inout LogicKernelContext) throws -> MappedGateDesign {
        try validate(identities, top: top, naming: naming, context: &context)
        let bytes = try decodingScratch(data.count, identities: identities, context: &context)
        let reservation = try context.reserveStorage(byteCount: bytes)
        let decoded: MappedGateDesign
        do {
            try context.charge(.workUnits, amount: UInt64(data.count))
            decoded = try decodeBody(data, identities: identities, top: top,
                names: Names(naming: copy naming), context: &context)
        } catch { try context.releaseStorage(reservation); throw error }
        try context.releaseStorage(reservation)
        return decoded
    }

    private func decodeBody(_ data: Data, identities: borrowing MappedGateDesign, top: String,
                            names: Names, context: inout LogicKernelContext) throws -> MappedGateDesign {
        try NativeMappedGateRealizationValidator().validate(identities, policy: .standardNetlist, context: &context)
        try context.charge(.expansion, amount: UInt64(data.count))
        guard let text = String(data: data, encoding: .utf8) else { throw LogicKernelError.invalidInput("Netlist is not UTF-8") }
        var reader = try Reader(text, strict: names.named)
        return try identities.withTables { nets, instances, _, ports, originalBits, _ in
            try reader.expect("module"); try reader.expectIdentifier(top); try reader.expect("(")
            var first = true
            for p in ports.indices {
                for b in 0..<ports[p].bits.count {
                    if !first { try reader.expect(",") }; first = false
                    try reader.expectIdentifier(names.port(ports[p].id, p, b))
                }
            }
            try reader.expect(")"); try reader.expect(";")
            for p in ports.indices {
                for b in 0..<ports[p].bits.count {
                    try reader.expect(ports[p].direction == .input ? "input" : "output")
                    try reader.expectIdentifier(names.port(ports[p].id, p, b)); try reader.expect(";")
                }
            }
            for n in nets.indices {
                if try directPort(n, nets: nets, ports: ports, bits: originalBits, names: names, visit: { try context.charge(.workUnits, amount: $0) }) { continue }
                try reader.expect("wire"); try reader.expectIdentifier(names.net(nets[n].id, n)); try reader.expect(";")
            }
            var drivers = [MappedGateNet.Driver?](repeating: nil, count: nets.count)
            var portNets: [[MappedNetIndex]] = []
            for p in ports.indices {
                var connections: [MappedNetIndex] = []
                for b in 0..<ports[p].bits.count {
                    try context.charge(.workUnits)
                    let portName = try names.port(ports[p].id, p, b)
                    let direct = originalBits[ports[p].bits.lowerBound + b].rawValue
                    if names.named, try names.net(nets[direct].id, direct) == portName {
                        if ports[p].direction == .input {
                            guard drivers[direct] == nil else { throw LogicKernelError.invalidModel("Multiple input drivers") }
                            drivers[direct] = .input
                        }
                        connections.append(.init(direct)); continue
                    }
                    try reader.expect("assign")
                    let net: Int
                    if ports[p].direction == .input {
                        net = try reader.net(nets: nets, names: names, context: &context); try reader.expect("="); try reader.expectIdentifier(portName)
                        guard drivers[net] == nil else { throw LogicKernelError.invalidModel("Multiple input drivers") }
                        drivers[net] = .input
                    } else {
                        try reader.expectIdentifier(portName); try reader.expect("="); net = try reader.net(nets: nets, names: names, context: &context)
                    }
                    try reader.expect(";"); connections.append(.init(net))
                }
                portNets.append(connections)
            }
            while reader.peek == "assign" && (!names.named || reader.peekIsBare) {
                try reader.expect("assign"); let n = try reader.net(nets: nets, names: names, context: &context); try reader.expect("=")
                let value = try reader.takeBare()
                guard value == "1'b0" || value == "1'b1", drivers[n] == nil else {
                    throw LogicKernelError.invalidModel("Invalid or duplicate binary constant driver")
                }
                drivers[n] = .constant(value == "1'b1"); try reader.expect(";")
            }
            var cellIndices: [LogicCellIndex] = []; var connections: [[MappedNetIndex]] = []
            for i in instances.indices {
                try context.checkpoint()
                let cellName = try reader.identifier(); var cellIndex: LogicCellIndex?
                try identities.library.withCells { cells in
                    for c in cells.indices {
                        if names.named { try context.charge(.workUnits, amount: UInt64(cells[c].name.utf8.count) + UInt64(cellName.utf8.count) + 1) }
                        if cells[c].name == cellName {
                            guard cellIndex == nil else { throw LogicKernelError.invalidModel("Ambiguous library cell name") }
                            cellIndex = .init(c)
                        }
                    }
                }
                guard let cellIndex else { throw LogicKernelError.invalidModel("Unknown physical cell") }
                let cell = try identities.library.cell(at: cellIndex)
                try reader.expectIdentifier(names.instance(instances[i].id, i)); try reader.expect("(")
                var pins = [MappedNetIndex?](repeating: nil, count: cell.pinCount)
                for ordinal in 0..<cell.pinCount {
                    if ordinal > 0 { try reader.expect(",") }
                    try reader.expect("."); let name = try reader.identifier(); var slot: Int?
                    for p in 0..<cell.pinCount {
                        let expected = try cell.pin(at: .init(p)).name
                        if names.named { try context.charge(.workUnits, amount: UInt64(expected.utf8.count) + UInt64(name.utf8.count) + 1) }
                        if expected == name { slot = p }
                    }
                    guard let slot, pins[slot] == nil else { throw LogicKernelError.invalidModel("Unknown or duplicate physical pin") }
                    try reader.expect("("); let n = try reader.net(nets: nets, names: names, context: &context); try reader.expect(")")
                    pins[slot] = .init(n)
                    if try cell.pin(at: .init(slot)).direction == .output {
                        guard drivers[n] == nil else { throw LogicKernelError.invalidModel("Multiple physical output drivers") }
                        drivers[n] = .instanceOutput(.init(i), .init(slot))
                    }
                }
                try reader.expect(")"); try reader.expect(";")
                cellIndices.append(cellIndex); connections.append(pins.map { $0! })
            }
            try reader.expect("endmodule")
            guard reader.peek == nil, drivers.allSatisfy({ $0 != nil }) else {
                throw LogicKernelError.invalidModel("Unconsumed syntax or undriven structural net")
            }
            var pinCount = 0; var bitCount = 0
            for pins in connections {
                let sum = pinCount.addingReportingOverflow(pins.count)
                guard !sum.overflow else { throw LogicKernelError.invalidInput("Netlist pin count overflows") }; pinCount = sum.partialValue
            }
            for bits in portNets {
                let sum = bitCount.addingReportingOverflow(bits.count)
                guard !sum.overflow else { throw LogicKernelError.invalidInput("Netlist port count overflows") }; bitCount = sum.partialValue
            }
            var builder = try MappedGateBuilder(library: identities.library,
                capacity: MappedGraphCapacity(nets: nets.count, instances: instances.count,
                    pinConnections: pinCount, ports: ports.count, portBits: bitCount), context: &context)
            for n in nets.indices {
                _ = try builder.addNet(.init(id: nets[n].id, driver: drivers[n]!, origin: nets[n].origin), context: &context)
            }
            for i in instances.indices {
                _ = try builder.addInstance(id: instances[i].id, cell: cellIndices[i], pinNets: connections[i],
                    stateID: instances[i].stateID, initialValue: instances[i].initialValue,
                    origin: instances[i].origin, context: &context)
            }
            for p in ports.indices {
                try builder.addPort(id: ports[p].id, direction: ports[p].direction, nets: portNets[p], context: &context)
            }
            return try builder.finish(context: &context)
        }
    }

    private func validateIdentifier(_ value: String) throws {
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw LogicKernelError.unsupported("Verilog identifiers require printable ASCII without whitespace")
        }
    }

    private struct Names {
        let naming: MappedGateVerilogNaming?
        init(naming: MappedGateVerilogNaming? = nil) { self.naming = naming }
        var named: Bool { naming != nil }
        func net(_ id: DesignEntityID, _ index: Int) throws -> String {
            guard let naming else { return "n\(index)" }
            guard let value = naming.netNames[id] else { throw LogicKernelError.invalidInput("Missing structural net name") }
            return value
        }
        func instance(_ id: DesignEntityID, _ index: Int) throws -> String {
            guard let naming else { return "i\(index)" }
            guard let value = naming.instanceNames[id] else { throw LogicKernelError.invalidInput("Missing structural instance name") }
            return value
        }
        func port(_ id: DesignEntityID, _ index: Int, _ bit: Int) throws -> String {
            guard let naming else { return "p\(index)_\(bit)" }
            guard let values = naming.portBitNames[id], values.indices.contains(bit) else {
                throw LogicKernelError.invalidInput("Missing structural port bit name")
            }
            return values[bit]
        }
    }

    private enum Emission { case text(String), work(UInt64) }

    private func account(_ emission: Emission, context: inout LogicKernelContext) throws(LogicKernelError) {
        switch emission {
        case .text(let fragment): try context.charge(.workUnits, amount: UInt64(fragment.utf8.count) + 1)
        case .work(let count): try context.charge(.workUnits, amount: count)
        }
    }

    private func adding(_ a: UInt64, _ b: UInt64) throws -> UInt64 {
        let sum = a.addingReportingOverflow(b)
        guard !sum.overflow else { throw LogicKernelError.invalidInput("Verilog workspace size overflows") }
        return sum.partialValue
    }

    private func product(_ a: Int, _ b: Int) throws -> UInt64 {
        let value = UInt64(a).multipliedReportingOverflow(by: UInt64(b))
        guard !value.overflow else { throw LogicKernelError.invalidInput("Verilog workspace size overflows") }
        return value.partialValue
    }

    private func directPort(_ n: Int, nets: borrowing Span<MappedGateNet>, ports: borrowing Span<MappedGatePort>,
                            bits: borrowing Span<MappedNetIndex>, names: Names,
                            visit: (UInt64) throws -> Void) throws -> Bool {
        guard names.named else { return false }
        let net = try names.net(nets[n].id, n)
        for p in ports.indices {
            for b in 0..<ports[p].bits.count {
                let port = try names.port(ports[p].id, p, b)
                try visit(UInt64(net.utf8.count) + UInt64(port.utf8.count) + 1)
                if net == port && bits[ports[p].bits.lowerBound + b].rawValue == n { return true }
            }
        }
        return false
    }

    private func render(_ design: borrowing MappedGateDesign, top: String, names: Names,
                        emit: (Emission) throws -> Void) throws {
        func identifier(_ value: String, escaped: Bool) throws {
            try emit(.work(UInt64(value.utf8.count) + 1))
            try validateIdentifier(value)
            if escaped { try emit(.text("\\")) }
            try emit(.text(value))
            if escaped { try emit(.text(" ")) }
        }
        try design.withTables { nets, instances, pins, ports, bits, _ in
            for index in instances.indices {
                try emit(.work(1)); try instances[index].requirePhysicalStartupRealization()
            }
            try emit(.text("module ")); try identifier(top, escaped: true); try emit(.text("("))
            var first = true
            for p in ports.indices {
                for b in 0..<ports[p].bits.count {
                    if !first { try emit(.text(",")) }; first = false
                    try identifier(names.port(ports[p].id, p, b), escaped: names.named)
                }
            }
            try emit(.text(");\n"))
            for p in ports.indices {
                for b in 0..<ports[p].bits.count {
                    try emit(.text(ports[p].direction == .input ? "input " : "output "))
                    try identifier(names.port(ports[p].id, p, b), escaped: names.named); try emit(.text(";\n"))
                }
            }
            for n in nets.indices {
                if try directPort(n, nets: nets, ports: ports, bits: bits, names: names, visit: { try emit(.work($0)) }) { continue }
                try emit(.text("wire ")); try identifier(names.net(nets[n].id, n), escaped: names.named); try emit(.text(";\n"))
            }
            for p in ports.indices {
                for b in 0..<ports[p].bits.count {
                    let n = bits[ports[p].bits.lowerBound + b].rawValue
                    let port = try names.port(ports[p].id, p, b), net = try names.net(nets[n].id, n)
                    try emit(.work(UInt64(port.utf8.count) + UInt64(net.utf8.count) + 1))
                    if names.named && port == net { continue }
                    try emit(.text("assign "))
                    try identifier(ports[p].direction == .input ? net : port, escaped: names.named)
                    try emit(.text("="))
                    try identifier(ports[p].direction == .input ? port : net, escaped: names.named)
                    try emit(.text(";\n"))
                }
            }
            for n in nets.indices {
                try emit(.work(1))
                if case .constant(let value) = nets[n].driver {
                    try emit(.text("assign ")); try identifier(names.net(nets[n].id, n), escaped: names.named)
                    try emit(.text(value ? "=1'b1;\n" : "=1'b0;\n"))
                }
            }
            for i in instances.indices {
                let cell = try design.library.cell(at: instances[i].cell)
                try identifier(cell.name, escaped: true)
                try identifier(names.instance(instances[i].id, i), escaped: names.named); try emit(.text("("))
                for p in 0..<cell.pinCount {
                    if p > 0 { try emit(.text(",")) }
                    try emit(.text(".")); try identifier(cell.pin(at: .init(p)).name, escaped: true)
                    try emit(.text("("))
                    let n = pins[instances[i].pins.lowerBound + p].rawValue
                    try identifier(names.net(nets[n].id, n), escaped: names.named); try emit(.text(")"))
                }
                try emit(.text(");\n"))
            }
            try emit(.text("endmodule\n"))
        }
    }

    private func validate(_ design: borrowing MappedGateDesign, top: String,
                          naming: borrowing MappedGateVerilogNaming,
                          context: inout LogicKernelContext) throws {
        func check(_ value: String) throws {
            try context.charge(.workUnits, amount: UInt64(value.utf8.count) + 1)
            try validateIdentifier(value)
        }
        func same(_ a: String, _ b: String) throws -> Bool {
            try context.charge(.workUnits, amount: UInt64(a.utf8.count) + UInt64(b.utf8.count) + 1)
            return a == b
        }
        try context.checkpoint(); try check(top)
        let owned = copy naming, names = Names(naming: copy naming)
        try design.withTables { nets, instances, _, ports, bits, _ in
            guard owned.netNames.count == nets.count, owned.instanceNames.count == instances.count,
                  owned.portBitNames.count == ports.count else { throw LogicKernelError.invalidInput("Naming must cover exactly the graph IDs") }
            for n in nets.indices {
                let value = try names.net(nets[n].id, n); try check(value)
                for old in 0..<n {
                    if try same(value, names.net(nets[old].id, old)) { throw LogicKernelError.invalidInput("Duplicate structural net name") }
                }
            }
            for p in ports.indices {
                guard owned.portBitNames[ports[p].id]?.count == ports[p].bits.count else {
                    throw LogicKernelError.invalidInput("Port naming differs from the exact bit shape")
                }
                for b in 0..<ports[p].bits.count {
                    let value = try names.port(ports[p].id, p, b); try check(value)
                    for oldPort in 0...p {
                        for oldBit in 0..<ports[oldPort].bits.count where oldPort < p || oldBit < b {
                            if try same(value, names.port(ports[oldPort].id, oldPort, oldBit)) {
                                throw LogicKernelError.invalidInput("Duplicate scalar port name")
                            }
                        }
                    }
                    for n in nets.indices {
                        if try same(value, names.net(nets[n].id, n)), bits[ports[p].bits.lowerBound + b].rawValue != n {
                            throw LogicKernelError.invalidInput("Port name collides with a different connected net")
                        }
                    }
                }
            }
            for i in instances.indices {
                let value = try names.instance(instances[i].id, i); try check(value)
                for old in 0..<i {
                    if try same(value, names.instance(instances[old].id, old)) { throw LogicKernelError.invalidInput("Duplicate instance name") }
                }
                for n in nets.indices {
                    if try same(value, names.net(nets[n].id, n)) { throw LogicKernelError.invalidInput("Instance and net names collide") }
                }
                for p in ports.indices {
                    for b in 0..<ports[p].bits.count {
                        if try same(value, names.port(ports[p].id, p, b)) { throw LogicKernelError.invalidInput("Instance and port names collide") }
                    }
                }
            }
        }
    }

    private func decodingScratch(_ count: Int, identities: borrowing MappedGateDesign,
                                 context: inout LogicKernelContext) throws -> UInt64 {
        var maximumPins = 0
        for index in 0..<identities.library.cellCount {
            try context.charge(.workUnits)
            maximumPins = max(maximumPins, try identities.library.cell(at: .init(index)).pinCount)
        }
        let pins = try product(identities.instanceCount, maximumPins)
        guard let pinCount = Int(exactly: pins) else { throw LogicKernelError.invalidInput("Decoder pin count overflows") }
        var bytes = try product(count, MemoryLayout<Reader.Token>.stride + 3)
        for (elements, stride) in [
            (identities.netCount, MemoryLayout<MappedGateNet.Driver?>.stride),
            (identities.portCount, MemoryLayout<[MappedNetIndex]>.stride),
            (identities.portBitCount, MemoryLayout<MappedNetIndex>.stride),
            (identities.instanceCount, MemoryLayout<LogicCellIndex>.stride + MemoryLayout<[MappedNetIndex]>.stride),
            (pinCount, MemoryLayout<MappedNetIndex?>.stride + MemoryLayout<MappedNetIndex>.stride)
        ] { bytes = try adding(bytes, product(elements, stride)) }
        return try adding(bytes, UInt64(MemoryLayout<Reader>.stride + MemoryLayout<String>.stride))
    }

    private struct Reader {
        typealias Token = MappedGateVerilogLexer.Token
        let tokens: [Token]; let strict: Bool; var index = 0
        var peek: String? { index < tokens.count ? tokens[index].value : nil }
        var peekIsBare: Bool { index < tokens.count && !tokens[index].escaped }
        init(_ text: String, strict: Bool) throws {
            self.strict = strict
            do { tokens = try MappedGateVerilogLexer.tokenize(text) }
            catch { throw LogicKernelError.invalidInput("Unterminated escaped identifier") }
        }
        mutating func take() throws -> String {
            guard let token = peek else { throw LogicKernelError.invalidInput("Truncated structural Verilog") }
            index += 1; return token
        }
        mutating func expect(_ token: String) throws {
            guard !strict || peekIsBare, try take() == token else { throw LogicKernelError.invalidInput("Unexpected structural Verilog token; expected \(token)") }
        }
        mutating func takeBare() throws -> String {
            guard !strict || peekIsBare else { throw LogicKernelError.invalidInput("Expected unescaped structural syntax") }
            return try take()
        }
        mutating func identifier() throws -> String {
            guard !strict || !peekIsBare else { throw LogicKernelError.invalidInput("Named profile requires escaped identifiers") }
            return try take()
        }
        mutating func expectIdentifier(_ token: String) throws {
            guard try identifier() == token else { throw LogicKernelError.invalidInput("Structural identifier differs") }
        }
        mutating func net(nets: borrowing Span<MappedGateNet>, names: Names,
                          context: inout LogicKernelContext) throws -> Int {
            let token = try identifier()
            if names.named {
                for index in nets.indices {
                    let expected = try names.net(nets[index].id, index)
                    try context.charge(.workUnits, amount: UInt64(token.utf8.count) + UInt64(expected.utf8.count) + 1)
                    if token == expected { return index }
                }
                throw LogicKernelError.invalidModel("Unknown named structural net")
            }
            guard token.first == "n", let value = Int(token.dropFirst()), value >= 0, value < nets.count,
                  token == "n\(value)" else { throw LogicKernelError.invalidModel("Unknown structural net") }
            return value
        }
    }
}
