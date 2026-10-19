import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogProgramCompiler {
    mutating func assign(_ signal: RTLSignalIndex, range: Range<Int>, value: RTLExpressionIndex,
        timing: RTLResolvedStatement.Timing, node: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        try builder.addStatement(RTLResolvedStatement(id: id(), operation: .assignment(target: signal, selection: range, value: value, timing: timing),
            origin: Self.origin(node, syntax: scope.constants.defaults.bindings.syntax)), context: &context)
    }
    mutating func converted(_ value: SystemVerilogResolvedExpression, width: Int, node: Int,
        scope: borrowing SystemVerilogSignalScope, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogResolvedExpression {
        if value.type.width.value == width { return value }
        let type = WordLogicType(width: try LogicBitWidth(width), isSigned: value.type.isSigned)
        let opcode: WordLogicOpcode = value.type.width.value > width ? .slice(offset: 0) : value.type.isSigned ? .signExtend : .zeroExtend
        return try emit(.compute(opcode), type: type, a: value.index, node: node, scope: scope, context: &context)
    }
    mutating func statement(_ node: Int, scope: inout SystemVerilogSignalScope, namespace: UInt64,
        procedural: Bool = true, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        let syntax = scope.constants.defaults.bindings.syntax
        try enter(node, syntax: syntax, context: &context); defer { depth -= 1 }
        switch try syntax.node(at: node).kind {
        case .empty, .declaration: return try empty(node, scope: scope, context: &context)
        case .group(let items): return try statements(items, node: node, scope: &scope, namespace: namespace, procedural: procedural, context: &context)
        case .block(_, let items):
            let constants = try scope.constants.entering(node, context: &context)
            var local = try bindScope(constants, parent: scope, namespace: namespace, context: &context)
            let body = try statements(items, node: node, scope: &local, namespace: namespace, procedural: procedural, context: &context)
            guard let parent = local.storage.parent else { throw .invalidModel("Block lost its lexical parent") }
            scope = parent; return body
        case .assignment(let operation, let targetNode, let value?):
            guard operation == .blocking || operation == .nonBlocking else { throw try Self.failure(node, scope: scope, "SV_ASSIGNMENT_KIND", "Procedural update is outside the admitted grammar") }
            if case .identifier(let name) = try syntax.node(at: targetNode).kind,
               let entry = try scope.constants.lookup(name, context: &context), let old = entry.value {
                guard operation == .blocking, !entry.isGenerateConstant,
                      case .declaration(.variable, _, _, _) = try syntax.node(at: entry.declaration).kind else {
                    throw try Self.failure(targetNode, scope: scope, "SV_STATIC_CONTROL_WRITE", "A frozen procedural control requires a blocking variable assignment")
                }
                let constant = try SystemVerilogConstantExpression.prepare(node: value, in: scope.constants, context: &context)
                let updated = try constant.evaluate(width: old.type.width.value, context: &context)
                let runtime = try runtimeBinding(name, in: scope, context: &context)
                let rhs = try expression(value, scope: scope, width: old.type.width.value, context: &context)
                scope = try scope.replacingControl(entry.declaration, with: updated, context: &context)
                if let runtime { return try assign(runtime.signal, range: 0..<old.type.width.value, value: rhs.index, timing: .blocking, node: node, scope: scope, context: &context) }
                return try empty(node, scope: scope, context: &context)
            }
            let width = try targetWidth(targetNode, scope: scope, context: &context)
            let rhs = try expression(value, scope: scope, width: width, context: &context)
            let known = try constantValue(value, width: width, scope: scope, context: &context)
            return try assignment(target: targetNode, rhs: rhs, timing: operation == .blocking ? .blocking : .nonBlocking,
                scope: &scope, namespace: namespace, procedural: procedural, knownRHS: known, context: &context)
        case .ifStatement(let condition, let yes, let no):
            let expression = try expression(condition, scope: scope, context: &context)
            let control = try truth(expression, node: condition, scope: scope, context: &context)
            let constant = try constantTruth(condition, scope: scope, context: &context)
            var yesScope = scope; var noScope = scope
            let ifTrue = try statement(yes, scope: &yesScope, namespace: namespace, procedural: procedural, context: &context)
            let ifFalse: RTLStatementIndex?
            if let no { ifFalse = try statement(no, scope: &noScope, namespace: namespace, procedural: procedural, context: &context) } else { ifFalse = nil }
            if let constant { scope = constant ? yesScope : noScope }
            else {
                guard try yesScope.sameControls(as: noScope, context: &context) else {
                    throw try Self.failure(node, scope: scope, "SV_RUNTIME_LOOP_CONTROL", "Runtime-dependent control updates cannot be statically unrolled")
                }
                scope = yesScope
            }
            return try builder.addStatement(RTLResolvedStatement(id: id(), operation: .conditional(condition: control, ifTrue: ifTrue, ifFalse: ifFalse), origin: Self.origin(node, syntax: syntax)), context: &context)
        case .caseStatement(let selector, let arms):
            return try caseStatement(node, selector: selector, arms: arms, scope: &scope, namespace: namespace, context: &context)
        case .forStatement: return try proceduralLoop(node, scope: &scope, namespace: namespace, context: &context)
        default: throw try Self.failure(node, scope: scope, "SV_PROCEDURAL_STATEMENT", "Syntax is not an admitted procedural statement")
        }
    }
    mutating func statements(_ items: Range<Int>, node: Int, scope: inout SystemVerilogSignalScope,
        namespace: UInt64, procedural: Bool = true, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        let scratch = try context.reserveStorage(byteCount: try SystemVerilogConstantEvaluator.bytes(items.count, MemoryLayout<RTLStatementIndex>.stride))
        let result: RTLStatementIndex
        do throws(LogicKernelError) {
            var body: [RTLStatementIndex] = []; body.reserveCapacity(items.count)
            for offset in items {
                let child = try scope.constants.defaults.bindings.syntax.child(at: offset)
                body.append(try statement(child, scope: &scope, namespace: namespace, procedural: procedural, context: &context))
            }
            result = try block(body, node: node, scope: scope, context: &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch); return result
    }
    borrowing func constantTruth(_ node: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Bool? {
        try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.constants.defaults, scope: scope.constants,
            signals: copy scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try evaluator.infer(node, context: &context)
            let metadata = try evaluator.metadata(node)
            if metadata.containsRuntime { return nil }
            let type = try metadata.type
            return try evaluator.evaluateExpression(node, width: type.width.value, signed: type.isSigned, context: &context).reducingBinary(.or, context: &context)
        }
    }
    borrowing func constantValue(_ node: Int, width: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector? {
        try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.constants.defaults, scope: scope.constants,
            signals: copy scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            try evaluator.infer(node, context: &context)
            let metadata = try evaluator.metadata(node)
            if metadata.containsRuntime { return nil }
            let type = try metadata.type
            let value = try evaluator.evaluateExpression(node, width: max(width,type.width.value), signed: type.isSigned, context: &context)
            return try value.resizedBinary(to: LogicBitWidth(width), signExtend: type.isSigned, context: &context)
        }
    }
}
