import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogSyntaxParser {
    internal mutating func continuousAssignment(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        try expect("assign", context: &context)
        var list = List()
        repeat {
            let target = try lvalue(context: &context); try expect("=", context: &context)
            let value = try expression(context: &context)
            let assignment = try add(.assignment(.blocking, target: target, value: value), start: start, context: &context)
            let process = try add(.process(.continuous, sensitivity: nil, body: assignment), start: start, context: &context)
            try append(process, to: &list, context: &context)
        } while try accept(",", context: &context)
        try expect(";", context: &context)
        return try add(.group(finish(list, context: &context)), start: start, context: &context)
    }
    internal mutating func process(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        let kind: SystemVerilogSyntaxNode.Process
        if try accept("always_comb", context: &context) { kind = .combinational }
        else if try accept("always_ff", context: &context) { kind = .flipFlop }
        else if try accept("always_latch", context: &context) { kind = .latch }
        else if try accept("initial", context: &context) { kind = .initial }
        else { try expect("always", context: &context); kind = .always }
        let sensitivity: Int?
        if kind == .always || kind == .flipFlop { sensitivity = try eventControl(context: &context) }
        else { sensitivity = nil }
        let body = try statement(context: &context)
        return try add(.process(kind, sensitivity: sensitivity, body: body), start: start, context: &context)
    }
    internal mutating func eventControl(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        try expect("@", context: &context)
        var list = List()
        if try accept("*", context: &context) {
            return try add(.sensitivity(all: true, terms: children.count..<children.count), start: start, context: &context)
        }
        try expect("(", context: &context)
        let all = try accept("*", context: &context)
        if !all {
            repeat {
                let eventStart = try current().byteRange.lowerBound
                let edge: SystemVerilogSyntaxNode.Edge
                if try accept("posedge", context: &context) { edge = .rising }
                else if try accept("negedge", context: &context) { edge = .falling }
                else { edge = .level }
                let value = try expression(context: &context)
                let term = try add(.event(edge, value), start: eventStart, context: &context)
                try append(term, to: &list, context: &context)
            } while try accept("or", ",", context: &context)
        }
        try expect(")", context: &context)
        return try add(.sensitivity(all: all, terms: finish(list, context: &context)), start: start, context: &context)
    }
    internal mutating func statement(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        try enter(context: &context); defer { depth -= 1 }
        let start = try current().byteRange.lowerBound
        if try accept(";", context: &context) { return try add(.empty, start: start, context: &context) }
        if try accept("begin", context: &context) {
            let label = try accept(":", context: &context) ? identifier(context: &context) : nil
            var list = List()
            while try !at("end", context: &context) {
                let item = try statement(context: &context); try append(item, to: &list, context: &context)
            }
            try expect("end", context: &context); try endLabel(label, context: &context)
            return try add(.block(label: label, statements: finish(list, context: &context)), start: start, context: &context)
        }
        if try accept("if", context: &context) {
            try expect("(", context: &context); let condition = try expression(context: &context); try expect(")", context: &context)
            let then = try statement(context: &context)
            let elseBody = try accept("else", context: &context) ? statement(context: &context) : nil
            return try add(.ifStatement(condition: condition, then: then, elseBody: elseBody), start: start, context: &context)
        }
        if try at("case", context: &context) { return try caseStatement(generate: false, context: &context) }
        if try at("casex", "casez", context: &context) {
            throw try failure("SV_SYNTHESIS_WILDCARD_CASE", "Only ordinary case belongs to the initial synthesis profile")
        }
        if try accept("for", context: &context) {
            let (initial, condition, step) = try loopControl(context: &context)
            let body = try statement(context: &context)
            return try add(.forStatement(initial: initial, condition: condition, step: step, body: body), start: start, context: &context)
        }
        if try beginsDeclaration(context: &context) { return try declaration(context: &context) }
        let result = try assignment(allowUpdate: false, context: &context)
        try expect(";", context: &context)
        return result
    }
    internal mutating func caseStatement(generate: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        try expect("case", context: &context)
        try expect("(", context: &context); let selector = try expression(context: &context); try expect(")", context: &context)
        var list = List()
        var hasDefault = false
        while try !at("endcase", context: &context) {
            let armStart = try current().byteRange.lowerBound
            var matches = List()
            if try accept("default", context: &context) {
                guard !hasDefault else { throw try failure("SV_SYNTAX_DUPLICATE_DEFAULT", "Case has more than one default") }
                hasDefault = true; _ = try accept(":", context: &context)
            } else {
                repeat {
                    let value = try expression(context: &context); try append(value, to: &matches, context: &context)
                } while try accept(",", context: &context)
                try expect(":", context: &context)
            }
            let body = try generate ? generateItem(context: &context) : statement(context: &context)
            let arm = try add(.caseArm(matches: finish(matches, context: &context), body: body), start: armStart, context: &context)
            try append(arm, to: &list, context: &context)
        }
        try expect("endcase", context: &context)
        let arms = try finish(list, context: &context)
        return try add(generate ? .generateCase(selector: selector, arms: arms) : .caseStatement(selector: selector, arms: arms), start: start, context: &context)
    }
    internal mutating func assignment(allowUpdate: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        if allowUpdate, try at("++", "--", context: &context) {
            let increment = try accept("++", context: &context)
            if !increment { try expect("--", context: &context) }
            let target = try lvalue(context: &context)
            return try add(.assignment(increment ? .increment : .decrement, target: target, value: nil), start: start, context: &context)
        }
        let target = try lvalue(context: &context)
        let kind: SystemVerilogSyntaxNode.Assignment
        if try accept("=", context: &context) { kind = .blocking }
        else if try accept("<=", context: &context) { kind = .nonBlocking }
        else if allowUpdate, try accept("+=", context: &context) { kind = .add }
        else if allowUpdate, try accept("-=", context: &context) { kind = .subtract }
        else if allowUpdate, try accept("++", context: &context) {
            return try add(.assignment(.increment, target: target, value: nil), start: start, context: &context)
        } else if allowUpdate, try accept("--", context: &context) {
            return try add(.assignment(.decrement, target: target, value: nil), start: start, context: &context)
        } else { throw try failure("SV_SYNTAX_EXPECTED_ASSIGNMENT", "Expected a supported assignment") }
        let value = try expression(context: &context)
        return try add(.assignment(kind, target: target, value: value), start: start, context: &context)
    }
    internal mutating func loopControl(context: inout LogicKernelContext)
        throws(LogicKernelError) -> (Int, Int, Int) {
        try expect("(", context: &context)
        let start = try current().byteRange.lowerBound
        let initial: Int
        let genvar = try accept("genvar", context: &context)
        let type = genvar ? nil : try packedType(context: &context)
        if genvar || type != nil {
            let name = try identifier(context: &context); try expect("=", context: &context)
            let value = try expression(context: &context)
            initial = try add(.declaration(genvar ? .genvar : .variable, name: name, type: type, initial: value), start: start, context: &context)
        } else { initial = try assignment(allowUpdate: false, context: &context) }
        try expect(";", context: &context)
        let condition = try expression(context: &context); try expect(";", context: &context)
        let step = try assignment(allowUpdate: true, context: &context); try expect(")", context: &context)
        return (initial, condition, step)
    }
    internal mutating func generateItem(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        try enter(context: &context); defer { depth -= 1 }
        let start = try current().byteRange.lowerBound
        if try accept("begin", context: &context) {
            let label = try accept(":", context: &context) ? identifier(context: &context) : nil
            var list = List()
            while try !at("end", context: &context) {
                let item = try moduleItem(context: &context); try append(item, to: &list, context: &context)
            }
            try expect("end", context: &context); try endLabel(label, context: &context)
            return try add(.generateBlock(label: label, items: finish(list, context: &context)), start: start, context: &context)
        }
        if try accept("if", context: &context) {
            try expect("(", context: &context); let condition = try expression(context: &context); try expect(")", context: &context)
            let then = try generateItem(context: &context)
            let elseBody = try accept("else", context: &context) ? generateItem(context: &context) : nil
            return try add(.generateIf(condition: condition, then: then, elseBody: elseBody), start: start, context: &context)
        }
        if try accept("for", context: &context) {
            let (initial, condition, step) = try loopControl(context: &context)
            let body = try generateItem(context: &context)
            return try add(.generateFor(initial: initial, condition: condition, step: step, body: body), start: start, context: &context)
        }
        if try at("case", context: &context) { return try caseStatement(generate: true, context: &context) }
        return try moduleItem(context: &context)
    }
    internal mutating func endLabel(_ declared: Int?, context: inout LogicKernelContext) throws(LogicKernelError) {
        if try accept(":", context: &context) {
            let labelRange = try current().byteRange
            let label = try identifier(context: &context)
            guard declared == label else {
                throw try failure("SV_SYNTAX_END_LABEL", "Block end label differs from its declaration", at: labelRange)
            }
        }
    }
}
