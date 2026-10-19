import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
internal struct SystemVerilogLoopControlEvaluation {
    private static func withBinding<Result>(_ binding: borrowing SystemVerilogLoopBinding,
        value: LogicFourStateVector?, shadow: Bool = true, scope: borrowing SystemVerilogConstantScope,
        context: inout LogicKernelContext,
        _ body: (inout SystemVerilogConstantEvaluator, inout LogicKernelContext) throws(LogicKernelError) -> Result
    ) throws(LogicKernelError) -> Result {
        let scratch = try context.reserveStorage(byteCount: UInt64(MemoryLayout<SystemVerilogScopeEntry>.stride))
        let result: Result
        do throws(LogicKernelError) {
            result = try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.defaults, scope: copy scope, context: &context) {
                (evaluator, context) throws(LogicKernelError) in
                if shadow { evaluator.lexicalEntries = [binding.entry(value: value)] }
                return try body(&evaluator, &context)
            }
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }
    static func initialize(_ binding: borrowing SystemVerilogLoopBinding,
        scope: borrowing SystemVerilogConstantScope, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicFourStateVector {
        try withBinding(binding, value: nil, shadow: !binding.isGenerate, scope: scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try evaluator.infer(binding.initializer, context: &context)
            let type = try evaluator.metadata(binding.initializer).type
            let value = try evaluator.evaluateExpression(binding.initializer, width: binding.type.width.value,
                signed: type.isSigned, context: &context)
            return try value.resizedBinary(to: binding.type.width, signExtend: type.isSigned, context: &context)
        }
    }
    static func condition(_ condition: Int, binding: borrowing SystemVerilogLoopBinding,
        value: borrowing LogicFourStateVector, scope: borrowing SystemVerilogConstantScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        try withBinding(binding, value: copy value, scope: scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try evaluator.infer(condition, context: &context)
            let type = try evaluator.metadata(condition).type
            let result = try evaluator.evaluateExpression(condition, width: type.width.value, signed: type.isSigned, context: &context)
            return try result.reducingBinary(.or, context: &context)
        }
    }
    static func update(_ step: Int, binding: borrowing SystemVerilogLoopBinding,
        value: borrowing LogicFourStateVector, scope: borrowing SystemVerilogConstantScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector {
        try withBinding(binding, value: copy value, scope: scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try update(step, binding: binding, value: value, evaluator: &evaluator, context: &context)
        }
    }
    private static func update(_ step: Int, binding: borrowing SystemVerilogLoopBinding,
        value: borrowing LogicFourStateVector, evaluator: inout SystemVerilogConstantEvaluator,
        context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector {
        guard case .assignment(let operation, _, let rhs) = try evaluator.syntax.node(at: step).kind else {
            throw .invalidModel("Static step is not an assignment")
        }
        let right: LogicFourStateVector; let signed: Bool; let width: Int
        if let rhs {
            try evaluator.infer(rhs, context: &context)
            let type = try evaluator.metadata(rhs).type
            signed = operation == .blocking ? type.isSigned : binding.type.isSigned && type.isSigned
            width = max(binding.type.width.value, type.width.value)
            right = try evaluator.evaluateExpression(rhs, width: width, signed: signed, context: &context)
        } else {
            guard operation == .increment || operation == .decrement else { throw .invalidModel("Static step has no RHS") }
            signed = binding.type.isSigned; width = max(binding.type.width.value, 32)
            let bitWidth = try LogicBitWidth(width)
            _ = try context.reserveStorage(byteCount: UInt64(bitWidth.wordCount) * 16)
            var words = [UInt64](repeating: 0, count: bitWidth.wordCount); words[0] = 1
            right = try LogicFourStateVector(width: bitWidth, valueWords: words,
                unknownWords: [UInt64](repeating: 0, count: bitWidth.wordCount))
        }
        if operation == .blocking { return try right.resizedBinary(to: binding.type.width, signExtend: signed, context: &context) }
        let left = try value.resizedBinary(to: LogicBitWidth(width), signExtend: signed, context: &context)
        let result: LogicFourStateVector
        switch operation {
        case .add, .increment: result = try left.addingBinary(right, context: &context)
        case .subtract, .decrement: result = try left.subtractingBinary(right, context: &context)
        case .blocking, .nonBlocking: throw .invalidModel("Unexpected static step operation")
        }
        return try result.resizedBinary(to: binding.type.width, signExtend: signed, context: &context)
    }
}
