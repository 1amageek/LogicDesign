import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogConstantEvaluator {
    internal static func withExpressionWorkspace<Result>(_ defaults: borrowing SystemVerilogParameterDefaults,
        scope: SystemVerilogConstantScope? = nil, signals: SystemVerilogSignalScope? = nil,
        writableRoot: Int? = nil, context: inout LogicKernelContext,
        _ body: (inout Self, inout LogicKernelContext) throws(LogicKernelError) -> Result
    ) throws(LogicKernelError) -> Result {
        try context.checkpoint()
        let count = defaults.bindings.syntax.nodeCount
        let temporary = try bytes(count, workspaceStride + (writableRoot == nil ? 0 : MemoryLayout<Bool>.stride))
        let scratch = try context.reserveStorage(byteCount: temporary)
        let result: Result
        do throws(LogicKernelError) {
            // Parameter payload is immutable and shared. Only workspace tables are allocated here.
            var evaluator = Self(bindings: defaults.bindings, parameters: defaults.valuesForEvaluation,
                info: [Info?](repeating: nil, count: count), allowModuleLookup: true, lexicalParent: scope)
            evaluator.signalScope = signals
            evaluator.pending.reserveCapacity(count * 2); evaluator.frames.reserveCapacity(count * 2)
            evaluator.values.reserveCapacity(count)
            if let writableRoot {
                evaluator.writableSelections = [Bool](repeating: false, count: count)
                evaluator.pending.append(writableRoot)
                while let node = evaluator.pending.popLast() {
                    try context.charge(.workUnits)
                    guard evaluator.writableSelections.indices.contains(node) else { throw .invalidModel("Invalid writable syntax reference") }
                    if evaluator.writableSelections[node] { continue }
                    evaluator.writableSelections[node] = true
                    switch try evaluator.syntax.node(at: node).kind {
                    case .identifier: break
                    case .select(_, let base, _, _): evaluator.pending.append(base)
                    case .concatenate(let children):
                        for offset in children { evaluator.pending.append(try evaluator.syntax.child(at: offset)) }
                    default: throw try evaluator.failure(node,"SV_ASSIGNMENT_TARGET","Assignment target must be a packed signal, selection or concatenation")
                    }
                }
                try evaluator.infer(writableRoot, context: &context)
            }
            result = try body(&evaluator, &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }

    internal mutating func admitOverrides(_ supplied: borrowing [SystemVerilogParameterOverride],
        context: inout LogicKernelContext) throws(LogicKernelError) {
        if supplied.isEmpty { return }
        overrides = [SystemVerilogConstantExpression?](repeating: nil, count: syntax.nodeCount)
        for index in supplied.indices {
            try context.charge(.workUnits)
            let override = supplied[index]
            guard bindings.sharesScope(with: override.bindings), override.declaration >= 0 && override.declaration < syntax.nodeCount,
                  case .declaration(_, let name, _, _) = try syntax.node(at: override.declaration).kind,
                  try bindings.declaration(named: name) == override.declaration else {
                throw .invalidInput("Override target is not a declaration in the child parameter scope")
            }
            guard try bindings.isOverridable(override.declaration, context: &context) else {
                throw try failure(override.declaration, "SV_PARAMETER_LOCAL_OVERRIDE", "A local parameter cannot be overridden")
            }
            guard overrides[override.declaration] == nil else {
                throw try failure(override.declaration, "SV_PARAMETER_DUPLICATE_OVERRIDE", "A parameter has more than one override")
            }
            overrides[override.declaration] = override.expression
        }
    }
}
