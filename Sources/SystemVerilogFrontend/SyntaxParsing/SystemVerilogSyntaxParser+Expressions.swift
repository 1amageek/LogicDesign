import LogicKernelCore
import LogicIR

@available(macOS 26.0, *)
extension SystemVerilogSyntaxParser {
    internal static let unsupportedOperators = ["/", "%", "**"]
    internal static let literalBases: [UInt8] = [98, 66, 100, 68, 104, 72, 111, 79]
    internal static let binaryOperators: [(String, SystemVerilogSyntaxNode.Binary, Int)] = [
        ("*", .multiply, 11), ("+", .add, 10), ("-", .subtract, 10),
        ("<<", .shiftLeft, 9), (">>", .shiftRight, 9), ("<<<", .arithmeticLeft, 9), (">>>", .arithmeticRight, 9),
        ("<", .less, 8), ("<=", .lessEqual, 8), (">", .greater, 8), (">=", .greaterEqual, 8),
        ("==", .equal, 7), ("!=", .notEqual, 7), ("===", .caseEqual, 7), ("!==", .caseNotEqual, 7),
        ("&", .and, 6), ("^", .xor, 5), ("~^", .xnor, 5), ("^~", .xnor, 5), ("|", .or, 4),
        ("&&", .logicalAnd, 3), ("||", .logicalOr, 2)
    ]
    internal static let unaryOperators: [(String, SystemVerilogSyntaxNode.Unary)] = [
        ("+", .plus), ("-", .minus), ("~", .invert), ("!", .logicalNot),
        ("&", .reduceAnd), ("|", .reduceOr), ("^", .reduceXor), ("~&", .reduceNand),
        ("~|", .reduceNor), ("~^", .reduceXnor), ("^~", .reduceXnor)
    ]
    internal mutating func expression(minimum: Int = 1, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        try enter(context: &context); defer { depth -= 1 }
        let start = try current().byteRange.lowerBound
        var left = try prefix(context: &context)
        while true {
            for unsupported in Self.unsupportedOperators {
                if try at(unsupported, context: &context) {
                    throw try failure("SV_SYNTHESIS_UNSUPPORTED_OPERATOR", "Division, remainder and power are outside the initial synthesis profile")
                }
            }
            var matched: (SystemVerilogSyntaxNode.Binary, Int)?
            for (spelling, operation, precedence) in Self.binaryOperators where precedence >= minimum {
                if try accept(spelling, context: &context) { matched = (operation, precedence); break }
            }
            if let (operation, precedence) = matched {
                let right = try expression(minimum: precedence + 1, context: &context)
                left = try add(.binary(operation, left, right), start: start, context: &context)
            } else { break }
        }
        if minimum <= 1, try accept("?", context: &context) {
            let then = try expression(context: &context); try expect(":", context: &context)
            let elseBody = try expression(context: &context)
            left = try add(.conditional(left, then, elseBody), start: start, context: &context)
        }
        return left
    }
    internal mutating func prefix(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let start = try current().byteRange.lowerBound
        for (spelling, operation) in Self.unaryOperators {
            if try accept(spelling, context: &context) {
                let operand = try expression(minimum: 12, context: &context)
                return try add(.unary(operation, operand), start: start, context: &context)
            }
        }
        let value: Int
        if try accept("(", context: &context) {
            value = try expression(context: &context); try expect(")", context: &context)
        } else if try accept("{", context: &context) {
            let first = try expression(context: &context)
            if try accept("{", context: &context) {
                let concatenation = try concatenation(first: nil, start: start, lvalue: false, context: &context)
                try expect("}", context: &context)
                value = try add(.repeated(first, concatenation), start: start, context: &context)
            } else {
                value = try concatenation(first: first, start: start, lvalue: false, context: &context)
            }
        } else if try at("$signed", "$unsigned", context: &context) {
            let signed = try at("$signed", context: &context)
            try advance(context: &context); try expect("(", context: &context)
            let operand = try expression(context: &context); try expect(")", context: &context)
            value = try add(.signedCast(signed, operand), start: start, context: &context)
        } else if try current().kind == .number {
            let first = try current(); try advance(context: &context)
            try context.charge(.workUnits, amount: UInt64(first.byteRange.count))
            // The grammar permits whitespace between a size, base and digit sequence.
            let followsSize = try stream.source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
                let next = try current()
                return next.kind == .number && !next.byteRange.isEmpty && bytes[next.byteRange.lowerBound] == 39
                    && !first.byteRange.contains(where: { bytes[$0] == 39 })
            }
            if followsSize { try advance(context: &context) }
            let last = try stream.token(at: position - 1)
            try context.charge(.workUnits, amount: UInt64(last.byteRange.count))
            let needsDigits = stream.source.withBytes { bytes in
                var index = last.byteRange.lowerBound
                while index < last.byteRange.upperBound && bytes[index] != 39 { index += 1 }
                if index == last.byteRange.upperBound { return false }
                index += 1
                if index < last.byteRange.upperBound && (bytes[index] == 115 || bytes[index] == 83) { index += 1 }
                guard index + 1 == last.byteRange.upperBound else { return false }
                return Self.literalBases.contains(bytes[index])
            }
            let nextKind = try current().kind
            if needsDigits && (nextKind == .number || nextKind == .identifier) {
                try advance(context: &context)
            }
            value = try add(.literal, start: start, context: &context)
        } else {
            let name = try identifier(context: &context)
            value = try add(.identifier(name), start: start, context: &context)
        }
        return try selections(value, start: start, context: &context)
    }
    internal mutating func selections(_ initial: Int, start: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        var value = initial
        while try accept("[", context: &context) {
            let first = try expression(context: &context)
            var selection = SystemVerilogSyntaxNode.Selection.bit
            var second: Int?
            if try accept(":", context: &context) { selection = .range; second = try expression(context: &context) }
            else if try accept("+:", context: &context) { selection = .indexedUp; second = try expression(context: &context) }
            else if try accept("-:", context: &context) { selection = .indexedDown; second = try expression(context: &context) }
            try expect("]", context: &context)
            value = try add(.select(selection, value: value, first: first, second: second), start: start, context: &context)
        }
        return value
    }
    internal mutating func lvalue(context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        try enter(context: &context); defer { depth -= 1 }
        let start = try current().byteRange.lowerBound
        if try accept("{", context: &context) {
            return try concatenation(first: nil, start: start, lvalue: true, context: &context)
        }
        let name = try identifier(context: &context)
        let value = try add(.identifier(name), start: start, context: &context)
        return try selections(value, start: start, context: &context)
    }
    internal mutating func concatenation(first: Int?, start: Int, lvalue: Bool,
                                         context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        var list = List()
        if let first { try append(first, to: &list, context: &context) }
        if first == nil {
            let value = try lvalue ? self.lvalue(context: &context) : expression(context: &context)
            try append(value, to: &list, context: &context)
        }
        while try accept(",", context: &context) {
            let value = try lvalue ? self.lvalue(context: &context) : expression(context: &context)
            try append(value, to: &list, context: &context)
        }
        try expect("}", context: &context)
        let range = try finish(list, context: &context)
        return try add(.concatenate(range), start: start, context: &context)
    }
}
