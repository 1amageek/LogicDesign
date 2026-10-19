import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogSyntaxParser {
    internal static let declarationStarters = ["input", "output", "inout", "wire", "var", "logic", "reg", "bit", "int", "integer", "signed", "unsigned", "parameter", "localparam", "genvar"]
    internal mutating func parseModule(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        try expect("module", context: &context)
        let name = try identifier(context: &context)
        let parameters: Range<Int>
        let hasParameterPortList = try accept("#", context: &context)
        if hasParameterPortList {
            try expect("(", context: &context)
            parameters = try parameterList(header: true, context: &context)
            try expect(")", context: &context)
        } else { parameters = children.count..<children.count }
        var ports = List()
        if try accept("(", context: &context) {
            var direction: SystemVerilogSyntaxNode.Direction?
            var inheritedType: Int?
            if try !at(")", context: &context) {
                repeat {
                    let portStart = try current().byteRange.lowerBound
                    if let next = try portDirection(context: &context) { direction = next; inheritedType = nil }
                    if let explicit = try packedType(context: &context) { inheritedType = explicit }
                    let portName = try identifier(context: &context)
                    try rejectUnpacked(context: &context)
                    let initial = try accept("=", context: &context) ? expression(context: &context) : nil
                    let port = try add(.port(direction, name: portName, type: inheritedType, initial: initial),
                                       start: portStart, context: &context)
                    try append(port, to: &ports, context: &context)
                } while try accept(",", context: &context)
            }
            try expect(")", context: &context)
        }
        let portRange = try finish(ports, context: &context)
        try expect(";", context: &context)
        var items = List()
        while try !at("endmodule", context: &context) {
            let item = try moduleItem(context: &context); try append(item, to: &items, context: &context)
        }
        try expect("endmodule", context: &context)
        if try accept(":", context: &context) {
            let labelRange = try current().byteRange
            let label = try identifier(context: &context)
            guard label == name else {
                throw try failure("SV_SYNTAX_END_LABEL", "Module end label differs from its declaration", at: labelRange)
            }
        }
        let itemRange = try finish(items, context: &context)
        return try add(.module(name: name, parameters: parameters, ports: portRange, items: itemRange, hasParameterPortList: hasParameterPortList), start: start, context: &context)
    }
    internal mutating func portDirection(context: inout LogicKernelContext) throws(LogicKernelError)
        -> SystemVerilogSyntaxNode.Direction? {
        if try accept("input", context: &context) { return .input }
        if try accept("output", context: &context) { return .output }
        if try accept("inout", context: &context) { return .inoutPort }
        return nil
    }
    internal mutating func packedType(context: inout LogicKernelContext) throws(LogicKernelError) -> Int? {
        let start = try current().byteRange.lowerBound
        var consumed = false
        var base = SystemVerilogSyntaxNode.BaseType.logic
        var storage = SystemVerilogSyntaxNode.Storage.unspecified
        var explicitBase = false
        if try accept("wire", context: &context) { consumed = true; storage = .net }
        else if try accept("var", context: &context) { consumed = true; storage = .variable }
        if try accept("logic", "reg", context: &context) { consumed = true; explicitBase = true }
        else if try accept("bit", context: &context) { consumed = true; explicitBase = true; base = .bit }
        else if try accept("int", context: &context) { consumed = true; explicitBase = true; base = .int }
        else if try accept("integer", context: &context) { consumed = true; explicitBase = true; base = .integer }
        var signed: Bool?
        if try accept("signed", context: &context) { consumed = true; signed = true }
        else if try accept("unsigned", context: &context) { consumed = true; signed = false }
        var dimensions = List()
        while try accept("[", context: &context) {
            consumed = true
            let rangeStart = previousEnd - 1
            let left = try expression(context: &context); try expect(":", context: &context)
            let right = try expression(context: &context); try expect("]", context: &context)
            let range = try add(.packedRange(left, right), start: rangeStart, context: &context)
            try append(range, to: &dimensions, context: &context)
        }
        guard consumed else { return nil }
        if (base == .int || base == .integer) && dimensions.count > 0 {
            throw try failure("SV_SYNTAX_INTEGER_PACKED_DIMENSION", "Integer atom types cannot declare packed dimensions")
        }
        let range = try finish(dimensions, context: &context)
        return try add(.type(base, signed: signed, dimensions: range, storage: storage, explicitBase: explicitBase), start: start, context: &context)
    }
    internal mutating func rejectUnpacked(context: inout LogicKernelContext) throws(LogicKernelError) {
        if try at("[", context: &context) {
            throw try failure("SV_SYNTHESIS_UNPACKED_STORAGE", "Unpacked storage and memory are outside the initial profile")
        }
    }
    internal mutating func parameterList(header: Bool, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Range<Int> {
        var list = List()
        var kind = SystemVerilogSyntaxNode.Declaration.parameter
        var inheritedType: Int?
        if header, try at(")", context: &context) { return children.count..<children.count }
        repeat {
            let start = try current().byteRange.lowerBound
            if try accept("parameter", context: &context) { kind = .parameter; inheritedType = nil }
            else if try accept("localparam", context: &context) { kind = .localParameter; inheritedType = nil }
            if let explicit = try packedType(context: &context) { inheritedType = explicit }
            let name = try identifier(context: &context); try rejectUnpacked(context: &context)
            try expect("=", context: &context)
            let value = try expression(context: &context)
            let node = try add(.declaration(kind, name: name, type: inheritedType, initial: value), start: start, context: &context)
            try append(node, to: &list, context: &context)
        } while try accept(",", context: &context)
        return try finish(list, context: &context)
    }
    internal mutating func declaration(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        if try at("parameter", "localparam", context: &context) {
            let list = try parameterList(header: false, context: &context); try expect(";", context: &context)
            return try add(.group(list), start: start, context: &context)
        }
        let direction = try portDirection(context: &context)
        let genvar = try accept("genvar", context: &context)
        let net = try at("wire", context: &context)
        let type = genvar ? nil : try packedType(context: &context)
        guard genvar || direction != nil || type != nil else {
            throw try failure("SV_SYNTAX_EXPECTED_DECLARATION", "Expected a packed-vector declaration")
        }
        var list = List()
        repeat {
            let declarationStart = try current().byteRange.lowerBound
            let name = try identifier(context: &context); try rejectUnpacked(context: &context)
            let initial = try accept("=", context: &context) ? expression(context: &context) : nil
            let kind: SystemVerilogSyntaxNode.Kind
            if let direction { kind = .port(direction, name: name, type: type, initial: initial) }
            else { kind = .declaration(genvar ? .genvar : net ? .net : .variable, name: name, type: type, initial: initial) }
            let node = try add(kind, start: declarationStart, context: &context)
            try append(node, to: &list, context: &context)
        } while try accept(",", context: &context)
        try expect(";", context: &context)
        return try add(.group(finish(list, context: &context)), start: start, context: &context)
    }
    internal mutating func beginsDeclaration(context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        for spelling in Self.declarationStarters {
            if try at(spelling, context: &context) { return true }
        }
        return false
    }
    internal mutating func moduleItem(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        try enter(context: &context); defer { depth -= 1 }
        let start = try current().byteRange.lowerBound
        if try beginsDeclaration(context: &context) { return try declaration(context: &context) }
        if try accept(";", context: &context) { return try add(.empty, start: start, context: &context) }
        if try at("assign", context: &context) { return try continuousAssignment(context: &context) }
        if try at("always", "always_comb", "always_ff", "always_latch", "initial", context: &context) {
            return try process(context: &context)
        }
        if try accept("generate", context: &context) {
            var list = List()
            while try !at("endgenerate", context: &context) {
                let item = try moduleItem(context: &context); try append(item, to: &list, context: &context)
            }
            try expect("endgenerate", context: &context)
            return try add(.generateRegion(finish(list, context: &context)), start: start, context: &context)
        }
        if try at("if", "for", "begin", "case", context: &context) {
            return try generateItem(context: &context)
        }
        if try at("`", context: &context) {
            // This internal grammar boundary requires already-preprocessed text.
            // Public source elaboration composes exact-bundle preprocessing first.
            throw try failure("SV_PREPROCESSING_REQUIRED", "Directives require source-bundle preprocessing")
        }
        return try instance(context: &context)
    }
    internal mutating func bindings(context: inout LogicKernelContext) throws(LogicKernelError) -> Range<Int> {
        try expect("(", context: &context)
        var list = List()
        if try !at(")", context: &context) {
            repeat {
                let start = try current().byteRange.lowerBound
                let name: Int?
                let value: Int?
                if try accept(".", context: &context) {
                    name = try identifier(context: &context); try expect("(", context: &context)
                    value = try at(")", context: &context) ? nil : expression(context: &context)
                    try expect(")", context: &context)
                } else {
                    name = nil
                    value = try at(",", ")", context: &context) ? nil : expression(context: &context)
                }
                let binding = try add(.binding(name: name, value: value), start: start, context: &context)
                try append(binding, to: &list, context: &context)
            } while try accept(",", context: &context)
        }
        try expect(")", context: &context)
        return try finish(list, context: &context)
    }
    internal mutating func instance(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        let module = try identifier(context: &context)
        let parameters = try accept("#", context: &context) ? bindings(context: &context) : children.count..<children.count
        var list = List()
        repeat {
            let name = try identifier(context: &context); try rejectUnpacked(context: &context)
            let ports = try bindings(context: &context)
            let node = try add(.instance(module: module, name: name, parameters: parameters, ports: ports), start: start, context: &context)
            try append(node, to: &list, context: &context)
        } while try accept(",", context: &context)
        try expect(";", context: &context)
        return try add(.group(finish(list, context: &context)), start: start, context: &context)
    }
}
