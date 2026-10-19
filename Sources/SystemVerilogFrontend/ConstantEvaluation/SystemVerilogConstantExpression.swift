import CircuiteFoundation
import LogicIR
import LogicKernelCore

package struct SystemVerilogConstantExpression: Sendable {
    package let type: SystemVerilogConstantType
    package let origin: LogicKernelSourceRange
    internal let node: Int
    internal let defaults: SystemVerilogParameterDefaults
    internal let scope: SystemVerilogConstantScope?

    @available(macOS 26.0, *)
    package static func prepare(node: Int, in defaults: borrowing SystemVerilogParameterDefaults,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        let syntax = defaults.bindings.syntax
        let root = try syntax.node(at: node)
        guard try SystemVerilogConstantScope.ownsModuleExpression(node, defaults: defaults, context: &context) else {
            throw .invalidInput("A module-default expression handle cannot enter a nested lexical scope")
        }
        let type = try SystemVerilogConstantEvaluator.withExpressionWorkspace(defaults, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try evaluator.infer(node, context: &context)
            guard try !evaluator.metadata(node).isEmpty else {
                throw try evaluator.failure(node, "SV_CONSTANT_EMPTY", "An initializer cannot be an empty repetition")
            }
            return try evaluator.metadata(node).type
        }
        return Self(type: type, origin: try syntax.source.origin(for: root.byteRange),
            node: node, defaults: copy defaults, scope: nil)
    }
    @available(macOS 26.0, *)
    package static func prepare(node: Int, in scope: borrowing SystemVerilogConstantScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        guard try scope.owns(node, context: &context) else {
            throw .invalidInput("Constant expression does not belong directly to its retained lexical scope")
        }
        let type = try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.defaults, scope: copy scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try evaluator.infer(node, context: &context)
            guard try !evaluator.metadata(node).isEmpty else {
                throw try evaluator.failure(node, "SV_CONSTANT_EMPTY", "An initializer cannot be an empty repetition")
            }
            return try evaluator.metadata(node).type
        }
        let syntax = scope.defaults.bindings.syntax; let root = try syntax.node(at: node)
        return Self(type: type, origin: try syntax.source.origin(for: root.byteRange),
            node: node, defaults: scope.defaults, scope: copy scope)
    }
    @available(macOS 26.0, *)
    package borrowing func evaluate(width: Int, signed: Bool, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicFourStateVector {
        guard width >= type.width.value else {
            throw .invalidInput("Common expression context cannot be narrower than its operand")
        }
        try context.observeBitWidth(UInt64(width))
        return try SystemVerilogConstantEvaluator.withExpressionWorkspace(defaults, scope: scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try evaluator.infer(node, context: &context)
            return try evaluator.evaluateExpression(node, width: width, signed: signed, context: &context)
        }
    }
    @available(macOS 26.0, *)
    package borrowing func evaluate(width: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicFourStateVector {
        guard width > 0 else { throw .invalidInput("Constant expression context width must be positive") }
        try context.observeBitWidth(UInt64(width))
        return try SystemVerilogConstantEvaluator.withExpressionWorkspace(defaults, scope: scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try evaluator.infer(node, context: &context)
            return try evaluator.evaluateExpression(node, width: width, signed: type.isSigned, context: &context)
        }
    }
}
