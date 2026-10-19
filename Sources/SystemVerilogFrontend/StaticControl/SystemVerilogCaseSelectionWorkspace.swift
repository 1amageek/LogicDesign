import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
internal struct SystemVerilogCaseSelectionWorkspace: ~Copyable {
    var expressions: [SystemVerilogConstantExpression] = []

    mutating func select(_ selector: Int, arms: Range<Int>,
        scope: borrowing SystemVerilogConstantScope, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int? {
        let syntax = scope.defaults.bindings.syntax
        expressions.append(try SystemVerilogConstantExpression.prepare(node: selector, in: scope, context: &context))
        var width = expressions[0].type.width.value
        var signed = expressions[0].type.isSigned
        var defaultBody: Int?
        // Every item contributes to the comparison context, even after a matching item.
        for offset in arms {
            try context.charge(.workUnits)
            guard case .caseArm(let matches, let body) = try syntax.node(at: syntax.child(at: offset)).kind else {
                throw .invalidModel("Malformed generate case arm")
            }
            if matches.isEmpty {
                guard defaultBody == nil else {
                    throw try SystemVerilogConstantScope.failure(body, in: syntax, "SV_CASE_DUPLICATE_DEFAULT", "A case has multiple defaults")
                }
                defaultBody = body
            }
            for match in matches {
                let expression = try SystemVerilogConstantExpression.prepare(node: syntax.child(at: match), in: scope, context: &context)
                width = max(width, expression.type.width.value); signed = signed && expression.type.isSigned
                expressions.append(expression)
            }
        }
        let selectorValue = try expressions[0].evaluate(width: width, signed: signed, context: &context)
        var index = 1
        for offset in arms {
            guard case .caseArm(let matches, let body) = try syntax.node(at: syntax.child(at: offset)).kind else {
                throw .invalidModel("Malformed generate case arm")
            }
            for _ in matches {
                try context.charge(.workUnits)
                let value = try expressions[index].evaluate(width: width, signed: signed, context: &context)
                if try selectorValue.equalsBinary(value, context: &context) { return body }
                index += 1
            }
        }
        return defaultBody
    }
}
