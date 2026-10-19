import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
package struct SystemVerilogExpressionCompiler {
    package static func compile(_ node: Int, in scope: borrowing SystemVerilogSignalScope,
        width: Int? = nil, signed: Bool? = nil, builder: inout ElaboratedRTLBuilder,
        nextEntityID: inout UInt64, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogResolvedExpression {
        guard try scope.constants.owns(node,context:&context) else {
            throw .invalidInput("Expression does not belong directly to its lexical owner")
        }
        let count = scope.constants.defaults.bindings.syntax.nodeCount
        let stride = MemoryLayout<SystemVerilogExpressionEmission.Frame>.stride * 2
            + MemoryLayout<SystemVerilogResolvedExpression>.stride + MemoryLayout<RTLExpressionIndex>.stride
        let scratch = try context.reserveStorage(byteCount:try SystemVerilogConstantEvaluator.bytes(count,stride))
        let result: SystemVerilogResolvedExpression
        do throws(LogicKernelError) {
            result = try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.constants.defaults,
                scope:scope.constants,signals:copy scope,context:&context) {
                (evaluator,context) throws(LogicKernelError) in
                try evaluator.infer(node,context:&context)
                guard try !evaluator.metadata(node).isEmpty else {
                    throw try evaluator.failure(node,"SV_CONSTANT_EMPTY","An expression cannot be an empty repetition")
                }
                let inferred = try evaluator.metadata(node).type
                let type = WordLogicType(width:try LogicBitWidth(width ?? inferred.width.value),isSigned:signed ?? inferred.isSigned)
                try context.observeBitWidth(UInt64(type.width.value))
                var emitter = SystemVerilogExpressionEmission()
                emitter.frames.reserveCapacity(count * 2);emitter.values.reserveCapacity(count)
                emitter.inputs.reserveCapacity(count)
                return try emitter.compile(node,type:type,evaluator:&evaluator,builder:&builder,
                    nextEntityID:&nextEntityID,context:&context)
            }
        } catch {try context.releaseStorage(scratch);throw error}
        try context.releaseStorage(scratch)
        return result
    }
}
