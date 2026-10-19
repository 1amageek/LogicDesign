import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
package struct SystemVerilogSyntaxParser: ~Copyable {
    internal struct List { var head = -1; var tail = -1; var count = 0 }
    internal struct Link { let value: Int; var next: Int }
    internal let stream: SystemVerilogTokenStream
    internal let limits: SystemVerilogSyntaxLimits
    internal var position = 0
    internal var previousEnd = 0
    internal var depth = 0
    internal var nodes: [SystemVerilogSyntaxNode] = []
    internal var children: [Int] = []
    internal var links: [Link] = []
    internal var symbols: [Range<Int>] = []
    internal var symbolNext: [Int] = []
    internal var symbolHeads: [UInt64: Int] = [:]

    package static func parse(_ stream: borrowing SystemVerilogTokenStream, limits: SystemVerilogSyntaxLimits,
                              context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogSyntaxTree {
        try context.checkpoint()
        let published = try storageSize([(limits.nodes, MemoryLayout<SystemVerilogSyntaxNode>.stride),
                                         (limits.children, MemoryLayout<Int>.stride),
                                         (limits.symbols, MemoryLayout<Range<Int>>.stride)])
        let temporary = try storageSize([(limits.children, MemoryLayout<Link>.stride),
                                         (limits.symbols, MemoryLayout<Int>.stride * 2 + MemoryLayout<UInt64>.stride)])
        let total = published.addingReportingOverflow(temporary)
        guard !total.overflow else { throw .invalidInput("Syntax storage overflow") }
        try context.require(.nodes, amount: UInt64(limits.nodes))
        try context.require(.edges, amount: UInt64(limits.children))
        try context.require(.managedStorageBytes, amount: total.partialValue)
        _ = try context.reserveStorage(byteCount: published)
        let scratch = try context.reserveStorage(byteCount: temporary)
        let result: SystemVerilogSyntaxTree
        do throws(LogicKernelError) {
            // The cursor retains the source owner; no token or source Span is stored.
            var parser = SystemVerilogSyntaxParser(stream: copy stream, limits: limits)
            parser.nodes.reserveCapacity(limits.nodes); parser.children.reserveCapacity(limits.children)
            parser.links.reserveCapacity(limits.children); parser.symbols.reserveCapacity(limits.symbols)
            parser.symbolNext.reserveCapacity(limits.symbols); parser.symbolHeads.reserveCapacity(limits.symbols)
            var modules = List()
            while try parser.current().kind != .endOfFile {
                guard try parser.at("module", context: &context) else {
                    throw try parser.failure("SV_SYNTAX_UNSUPPORTED_DESCRIPTION", "Expected a module declaration")
                }
                let module = try parser.parseModule(context: &context)
                try parser.append(module, to: &modules, context: &context)
            }
            let range = try parser.finish(modules, context: &context)
            result = parser.publish(modules: range)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }

    internal static func storageSize(_ tables: [(Int, Int)]) throws(LogicKernelError) -> UInt64 {
        var total: UInt64 = 0
        for (count, stride) in tables {
            let product = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let sum = total.addingReportingOverflow(product.partialValue)
            guard !product.overflow, !sum.overflow else { throw .invalidInput("Syntax storage overflow") }
            total = sum.partialValue
        }
        return total
    }
    internal consuming func publish(modules: Range<Int>) -> SystemVerilogSyntaxTree {
        SystemVerilogSyntaxTree(source: stream.source, nodes: nodes, children: children, symbols: symbols, modules: modules)
    }
    internal borrowing func current() throws(LogicKernelError) -> SystemVerilogLexicalToken {
        try stream.token(at: position)
    }
    internal mutating func advance(context: inout LogicKernelContext) throws(LogicKernelError) {
        let token = try current()
        guard token.kind != .endOfFile else { throw try failure("SV_SYNTAX_UNEXPECTED_EOF", "Unexpected end of source") }
        try context.charge(.workUnits)
        previousEnd = token.byteRange.upperBound; position += 1
    }
    internal borrowing func at(_ spelling: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        let token = try current()
        guard token.kind != .escapedIdentifier, token.byteRange.count == spelling.utf8.count else { return false }
        try context.charge(.workUnits, amount: UInt64(token.byteRange.count) + 1)
        return stream.source.withBytes { bytes in
            var offset = token.byteRange.lowerBound
            for byte in spelling.utf8 {
                if bytes[offset] != byte { return false }
                offset += 1
            }
            return true
        }
    }
    internal mutating func accept(_ spelling: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        guard try at(spelling, context: &context) else { return false }
        try advance(context: &context); return true
    }
    internal borrowing func at(_ a: String, _ b: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        if try at(a, context: &context) { return true }
        return try at(b, context: &context)
    }
    internal borrowing func at(_ a: String, _ b: String, _ c: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        if try at(a, context: &context) { return true }
        if try at(b, context: &context) { return true }
        return try at(c, context: &context)
    }
    internal borrowing func at(_ a: String, _ b: String, _ c: String, _ d: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        if try at(a, b, c, context: &context) { return true }
        return try at(d, context: &context)
    }
    internal borrowing func at(_ a: String, _ b: String, _ c: String, _ d: String, _ e: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        if try at(a, context: &context) { return true }
        if try at(b, context: &context) { return true }
        if try at(c, context: &context) { return true }
        if try at(d, context: &context) { return true }
        return try at(e, context: &context)
    }
    internal mutating func accept(_ first: String, _ second: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        if try accept(first, context: &context) { return true }
        return try accept(second, context: &context)
    }
    internal mutating func expect(_ spelling: String, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard try accept(spelling, context: &context) else {
            throw try failure("SV_SYNTAX_EXPECTED_TOKEN", "Expected " + spelling)
        }
    }
    internal borrowing func failure(_ code: String, _ message: String, at range: Range<Int>? = nil)
        throws(LogicKernelError) -> LogicKernelError {
        let location: Range<Int>
        if let range { location = range } else { location = try current().byteRange }
        return .sourceFailure(code: .trusted(code), source: try stream.source.origin(for: location), message: message)
    }
    internal mutating func enter(context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.charge(.workUnits)
        guard depth < limits.nesting else { throw try failure("SV_SYNTAX_NESTING_LIMIT", "Syntax nesting capacity exhausted") }
        depth += 1
    }
    internal mutating func add(_ kind: SystemVerilogSyntaxNode.Kind, start: Int,
                               context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        guard nodes.count < limits.nodes else {
            throw .resourceLimit(resource: .nodes, limit: UInt64(limits.nodes), requested: UInt64(nodes.count) + 1)
        }
        try context.charge(.nodes); try context.charge(.expansion)
        try context.charge(.edges, amount: UInt64(kind.referenceCount))
        nodes.append(SystemVerilogSyntaxNode(kind: kind, byteRange: start..<max(start, previousEnd)))
        return nodes.count - 1
    }
    internal mutating func append(_ value: Int, to list: inout List, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        guard links.count < limits.children else {
            throw .resourceLimit(resource: .edges, limit: UInt64(limits.children), requested: UInt64(links.count) + 1)
        }
        try context.charge(.edges); try context.charge(.workUnits)
        let index = links.count; links.append(Link(value: value, next: -1))
        if list.tail >= 0 { links[list.tail].next = index } else { list.head = index }
        list.tail = index; list.count += 1
    }
    internal mutating func finish(_ list: List, context: inout LogicKernelContext) throws(LogicKernelError) -> Range<Int> {
        let start = children.count
        var cursor = list.head
        while cursor >= 0 {
            try context.charge(.workUnits)
            children.append(links[cursor].value); cursor = links[cursor].next
        }
        return start..<children.count
    }
    internal mutating func identifier(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let token = try current()
        guard token.kind == .identifier || token.kind == .escapedIdentifier else {
            throw try failure("SV_SYNTAX_EXPECTED_IDENTIFIER", "Expected an identifier")
        }
        if token.kind == .identifier {
            try context.charge(.workUnits)
            if stream.source.withBytes({ $0[token.byteRange.lowerBound] == 36 }) {
                throw try failure("SV_SYNTAX_SYSTEM_IDENTIFIER", "A system name cannot be an ordinary identifier")
            }
            for keyword in Self.keywords {
                try context.charge(.workUnits)
                if keyword.utf8.count != token.byteRange.count { continue }
                if try at(keyword, context: &context) {
                    throw try failure("SV_SYNTAX_RESERVED_IDENTIFIER", "A keyword requires an escaped identifier")
                }
            }
        }
        let range = (token.byteRange.lowerBound + (token.kind == .escapedIdentifier ? 1 : 0))..<token.byteRange.upperBound
        let fingerprint = try stream.source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
            var hash: UInt64 = 0xcbf29ce484222325
            for index in range { try context.charge(.workUnits); hash = (hash ^ UInt64(bytes[index])) &* 0x100000001b3 }
            return hash
        }
        var cursor = symbolHeads[fingerprint] ?? -1
        while cursor >= 0 {
            try context.charge(.workUnits)
            let candidate = symbols[cursor]
            if candidate.count == range.count {
                let equal = try stream.source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
                    for offset in 0..<range.count {
                        try context.charge(.workUnits)
                        if bytes[range.lowerBound + offset] != bytes[candidate.lowerBound + offset] { return false }
                    }
                    return true
                }
                if equal { try advance(context: &context); return cursor }
            }
            cursor = symbolNext[cursor]
        }
        guard symbols.count < limits.symbols else {
            throw .resourceLimit(resource: .expansion, limit: UInt64(limits.symbols), requested: UInt64(symbols.count) + 1)
        }
        try context.charge(.expansion)
        let index = symbols.count; symbols.append(range)
        symbolNext.append(symbolHeads[fingerprint] ?? -1); symbolHeads[fingerprint] = index
        try advance(context: &context)
        return index
    }
    internal static let keywords = "accept_on alias always always_comb always_ff always_latch and assert assign assume automatic before begin bind bins binsof bit break buf bufif0 bufif1 byte case casex casez cell chandle checker class clocking cmos config const constraint context continue cover covergroup coverpoint cross deassign default defparam design disable dist do edge else end endcase endchecker endclass endclocking endconfig endfunction endgenerate endgroup endinterface endmodule endpackage endprimitive endprogram endproperty endsequence endspecify endtable endtask enum event eventually expect export extends extern final first_match for force foreach forever fork forkjoin function generate genvar global highz0 highz1 if iff ifnone ignore_bins illegal_bins implements implies import incdir include initial inout input inside int integer interconnect interface intersect join join_any join_none large let liblist library local localparam logic longint macromodule matches medium modport module nand negedge nettype new nexttime nmos nor noshowcancelled not notif0 notif1 null or output package packed parameter pmos posedge primitive priority program property protected pull0 pull1 pulldown pullup pulsestyle_ondetect pulsestyle_onevent pure rand randc randcase randsequence rcmos real realtime ref reg reject_on release repeat restrict return rnmos rpmos rtran rtranif0 rtranif1 s_always s_eventually s_nexttime s_until s_until_with scalared sequence shortint shortreal showcancelled signed small soft solve specify specparam static string strong strong0 strong1 struct super supply0 supply1 sync_accept_on sync_reject_on table tagged task this throughout time timeprecision timeunit tran tranif0 tranif1 tri tri0 tri1 triand trior trireg type typedef union unique unique0 unsigned until until_with untyped use uwire var vectored virtual void wait wait_order wand weak weak0 weak1 while wildcard wire with within wor xnor xor".split(separator: " ").map(String.init)
}
