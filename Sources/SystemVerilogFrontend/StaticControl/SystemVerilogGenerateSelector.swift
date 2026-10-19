import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
package struct SystemVerilogGenerateSelector {
    package static func select(_ node: Int, in scope: borrowing SystemVerilogConstantScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Int? {
        guard try scope.owns(node, context: &context) else {
            throw .invalidInput("Generate control is outside its lexical scope")
        }
        switch try scope.defaults.bindings.syntax.node(at: node).kind {
        case .generateIf(let condition, let yes, let no):
            let expression = try SystemVerilogConstantExpression.prepare(node: condition, in: scope, context: &context)
            let value = try expression.evaluate(width: expression.type.width.value, context: &context)
            return try value.reducingBinary(.or, context: &context) ? yes : no
        case .generateCase(let selector, let arms):
            return try selectCase(selector, arms: arms, scope: scope, context: &context)
        default: throw .invalidInput("Selection requires a conditional generate construct")
        }
    }
    private static func selectCase(_ selector: Int, arms: Range<Int>,
        scope: borrowing SystemVerilogConstantScope, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int? {
        let syntax = scope.defaults.bindings.syntax
        var count = 1
        for offset in arms {
            try context.charge(.workUnits)
            guard case .caseArm(let matches, _) = try syntax.node(at: syntax.child(at: offset)).kind else {
                throw .invalidModel("Malformed generate case arm")
            }
            let sum = count.addingReportingOverflow(matches.count)
            guard !sum.overflow else { throw .invalidInput("Case match count overflow") }
            count = sum.partialValue
        }
        let bytes = try SystemVerilogConstantEvaluator.bytes(count, MemoryLayout<SystemVerilogConstantExpression>.stride)
        let scratch = try context.reserveStorage(byteCount: bytes)
        let result: Int?
        do throws(LogicKernelError) {
            var workspace = SystemVerilogCaseSelectionWorkspace()
            workspace.expressions.reserveCapacity(count)
            result = try workspace.select(selector, arms: arms, scope: scope, context: &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }
}
