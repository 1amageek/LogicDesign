import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogProgramCompiler {
    mutating func proceduralLoop(_ node: Int, scope: inout SystemVerilogSignalScope,
        namespace: UInt64, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        let syntax = scope.constants.defaults.bindings.syntax
        guard case .forStatement(let initial, _, _, _) = try syntax.node(at: node).kind else { throw .invalidModel("Expected procedural loop") }
        let binding = try SystemVerilogLoopBinding.resolve(initial: initial, generate: false, scope: scope.constants, context: &context)
        let candidate = try runtimeBinding(binding.symbol, in: scope, context: &context)
        let runtime = candidate?.declaration == binding.declaration ? candidate : nil
        let scratch = try context.reserveStorage(byteCount: try SystemVerilogConstantEvaluator.bytes(capacity.children, MemoryLayout<RTLStatementIndex>.stride))
        let result: RTLStatementIndex
        do throws(LogicKernelError) {
            var statements: [RTLStatementIndex] = []; statements.reserveCapacity(capacity.children)
            var control = try SystemVerilogStaticLoop.prepare(node, in: scope.constants, context: &context)
            var iteration = try control.begin(context: &context)
            if let runtime {
                guard let first = iteration?.value ?? control.finalValue else { throw .invalidModel("Missing initialized loop value") }
                try appendControlWrite(first, runtime: runtime, node: node, scope: scope, statements: &statements, context: &context)
            }
            while let current = iteration {
                var local = try bindScope(current.scope, parent: scope, namespace: namespace, context: &context)
                let body = try statement(current.body, scope: &local, namespace: namespace, context: &context)
                guard statements.count < capacity.children else { throw .invalidInput("Unrolled program child capacity exhausted") }
                statements.append(body)
                guard let value = try local.frozenControl(current.declaration, context: &context),
                      let updatedParent = local.storage.parent else { throw .invalidModel("Loop body lost its control environment") }
                scope = updatedParent
                try control.refreshProceduralParent(scope.constants)
                iteration = try control.resume(afterBody: current, value: value.value, context: &context)
                if let runtime {
                    guard let next = iteration?.value ?? control.finalValue else { throw .invalidModel("Missing stepped loop value") }
                    try appendControlWrite(next, runtime: runtime, node: node, scope: scope, statements: &statements, context: &context)
                }
            }
            if try scope.frozenControl(binding.declaration, context: &context) != nil, let final = control.finalValue {
                scope = try scope.replacingControl(binding.declaration, with: final, context: &context)
            }
            result = try block(statements, node: node, scope: scope, context: &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch); return result
    }
    mutating func appendControlWrite(_ value: LogicFourStateVector, runtime: SystemVerilogSignalBinding,
        node: Int, scope: borrowing SystemVerilogSignalScope, statements: inout [RTLStatementIndex],
        context: inout LogicKernelContext) throws(LogicKernelError) {
        guard statements.count < capacity.children else { throw .invalidInput("Unrolled program child capacity exhausted") }
        let expression = try emit(.constant(value), type: WordLogicType(width: runtime.type.width, isSigned: runtime.type.isSigned),
            node: node, scope: scope, context: &context)
        statements.append(try assign(runtime.signal, range: 0..<runtime.type.width.value, value: expression.index, timing: .blocking,
            node: node, scope: scope, context: &context))
    }
    mutating func caseStatement(_ node: Int, selector: Int, arms: Range<Int>, scope: inout SystemVerilogSignalScope,
        namespace: UInt64, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        let syntax = scope.constants.defaults.bindings.syntax
        let comparison = try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.constants.defaults, scope: scope.constants,
            signals: scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) -> (type: SystemVerilogConstantType, known: Bool, selected: Int?) in
            try evaluator.infer(selector, context: &context)
            var type = try evaluator.metadata(selector).type
            var runtime = try evaluator.metadata(selector).containsRuntime
            var width = type.width.value; var signed = type.isSigned
            for offset in arms {
                guard case .caseArm(let matches, _) = try syntax.node(at: syntax.child(at: offset)).kind else { throw .invalidModel("Malformed case arm") }
                for match in matches {
                    let expression = try syntax.child(at: match)
                    try evaluator.infer(expression, context: &context)
                    let info = try evaluator.metadata(expression); let own = try info.type
                    width = max(width, own.width.value); signed = signed && own.isSigned; runtime = runtime || info.containsRuntime
                }
            }
            type = try SystemVerilogConstantType(width: width, signed: signed)
            if runtime { return (type, false, nil) }
            let value = try evaluator.evaluateExpression(selector, width: width, signed: signed, context: &context)
            var selected: Int?; var fallback: Int?
            for offset in arms {
                guard case .caseArm(let matches, _) = try syntax.node(at: syntax.child(at: offset)).kind else { throw .invalidModel("Malformed case arm") }
                if matches.isEmpty { fallback = offset }
                for match in matches {
                    let candidate = try evaluator.evaluateExpression(syntax.child(at: match), width: width, signed: signed, context: &context)
                    if selected == nil, try value.equalsBinary(candidate, context: &context) { selected = offset }
                }
            }
            return (type, true, selected ?? fallback)
        }
        var total = 0
        for offset in arms {
            guard case .caseArm(let matches, _) = try syntax.node(at: syntax.child(at: offset)).kind else { throw .invalidModel("Malformed case arm") }
            let sum = total.addingReportingOverflow(matches.count)
            guard !sum.overflow else { throw .invalidInput("Case match count overflow") }; total = sum.partialValue
        }
        let bytes = try SystemVerilogConstantEvaluator.bytes(total, MemoryLayout<RTLExpressionIndex>.stride)
        let records = try SystemVerilogConstantEvaluator.bytes(arms.count, MemoryLayout<(Int, Range<Int>, RTLStatementIndex)>.stride)
        let sum = bytes.addingReportingOverflow(records); guard !sum.overflow else { throw .invalidInput("Case workspace overflow") }
        let scratch = try context.reserveStorage(byteCount: sum.partialValue)
        let result: RTLStatementIndex
        do throws(LogicKernelError) {
            let selector = try expression(selector, scope: scope, width: comparison.type.width.value, signed: comparison.type.isSigned, context: &context)
            var matches: [RTLExpressionIndex] = []; matches.reserveCapacity(total)
            var items: [(node: Int, matches: Range<Int>, body: RTLStatementIndex)] = []; items.reserveCapacity(arms.count)
            var fallback: RTLStatementIndex?; var merged: SystemVerilogSignalScope?; var selected: SystemVerilogSignalScope?
            var hasDefault = false
            for offset in arms {
                let arm = try syntax.child(at: offset)
                guard case .caseArm(let values, let body) = try syntax.node(at: arm).kind else { throw .invalidModel("Malformed case arm") }
                let start = matches.count
                for value in values {
                    matches.append(try expression(syntax.child(at: value), scope: scope, width: comparison.type.width.value, signed: comparison.type.isSigned, context: &context).index)
                }
                var local = scope
                let statement = try statement(body, scope: &local, namespace: namespace, context: &context)
                if comparison.selected == offset { selected = local }
                if !comparison.known, let previous = merged, try !previous.sameControls(as: local, context: &context) {
                    throw try Self.failure(node, scope: scope, "SV_RUNTIME_LOOP_CONTROL", "Case-dependent control updates cannot be statically unrolled")
                }
                merged = local
                if values.isEmpty { fallback = statement; hasDefault = true }
                else { items.append((arm, start..<matches.count, statement)) }
            }
            if comparison.known { if let selected { scope = selected } }
            else if let merged {
                let agrees = try merged.sameControls(as: scope, context: &context)
                guard hasDefault || agrees else {
                    throw try Self.failure(node, scope: scope, "SV_RUNTIME_LOOP_CONTROL", "Case without default cannot establish a unique static control value")
                }
                scope = merged
            }
            // Nested case tables are complete before admitting this contiguous item range.
            let start = caseCount
            for item in items {
                let index = try builder.addCaseItem(matches: matches[item.matches], body: item.body,
                    origin: Self.origin(item.node, syntax: syntax), context: &context)
                guard index == caseCount else { throw .invalidModel("Case item ownership diverged") }; caseCount += 1
            }
            result = try builder.addStatement(RTLResolvedStatement(id: id(), operation: .caseStatement(selector: selector.index,
                items: start..<caseCount, defaultBody: fallback), origin: Self.origin(node, syntax: syntax)), context: &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch); return result
    }
}
