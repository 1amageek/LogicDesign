import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogConstantEvaluator {
    internal mutating func resolveConstant(_ symbol: Int, reference: Int,
        context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogConstant {
        if let declaration = try bindings.declaration(forReference: reference), let value = parameters[declaration] { return value }
        for entry in lexicalEntries {
            try context.charge(.workUnits)
            if entry.symbol == symbol {
                guard let value = entry.value else {
                    throw try failure(reference, "SV_SCOPE_NONCONSTANT_NAME", "Nearest declaration is not an available constant")
                }
                return value
            }
        }
        if let lexicalParent {
            guard let entry = try lexicalParent.lookup(symbol, context: &context), let value = entry.value else {
                throw try failure(reference, "SV_SCOPE_NONCONSTANT_NAME", "Nearest declaration is not an available constant")
            }
            return value
        }
        if allowModuleLookup, let declaration = try bindings.declaration(named: symbol), let value = parameters[declaration] { return value }
        throw try failure(reference, "SV_CONSTANT_UNRESOLVED_NAME", "Name is not a parameter in the expression's module scope")
    }
    internal static func scope(defaults: borrowing SystemVerilogParameterDefaults, container: Int,
        parent: SystemVerilogConstantScope?, entries: consuming [SystemVerilogScopeEntry],
        children: consuming [Int], iteration: LogicFourStateVector?, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogConstantScope {
        let count = defaults.bindings.syntax.nodeCount
        let scratch = try context.reserveStorage(byteCount: bytes(count, workspaceStride))
        let result: SystemVerilogConstantScope
        do throws(LogicKernelError) {
            var evaluator = Self(bindings: defaults.bindings, parameters: defaults.valuesForEvaluation,
                info: [Info?](repeating: nil, count: count), allowModuleLookup: true,
                lexicalParent: parent, lexicalEntries: entries)
            evaluator.pending.reserveCapacity(count * 2); evaluator.frames.reserveCapacity(count * 2)
            evaluator.values.reserveCapacity(count)
            try evaluator.bindScope(container: container, iteration: iteration, context: &context)
            try context.charge(.expansion)
            result = evaluator.publishScope(defaults: defaults, container: container, parent: parent, children: children)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }
    private mutating func bindScope(container: Int, iteration: LogicFourStateVector?,
        context: inout LogicKernelContext) throws(LogicKernelError) {
        switch try syntax.node(at: container).kind {
        case .forStatement(let initial, _, _, _):
            guard let iteration else { throw .invalidInput("Loop scope requires a frozen iteration value") }
            try bindIteration(initial: initial, capacity: container + 1, generate: false, value: iteration, context: &context)
        case .generateFor(let initial, _, _, _):
            guard let iteration else { throw .invalidInput("Loop scope requires a frozen iteration value") }
            try bindIteration(initial: initial, capacity: container + 1, generate: true, value: iteration, context: &context)
        default:
            guard iteration == nil else { throw .invalidInput("A non-loop scope cannot have an iteration binding") }
        }
        for index in lexicalEntries.indices {
            try context.charge(.workUnits)
            let node = lexicalEntries[index].declaration
            guard case .declaration(let kind, _, _, _) = try syntax.node(at: node).kind,
                  kind == .parameter || kind == .localParameter else { continue }
            let value = try declarationValue(node, context: &context)
            lexicalEntries[index].value = value
        }
    }
    private mutating func bindIteration(initial: Int, capacity: Int, generate: Bool,
        value: borrowing LogicFourStateVector, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard let lexicalParent else { throw .invalidModel("An iteration requires its lexical parent") }
        let binding = try SystemVerilogLoopBinding.resolve(initial: initial, generate: generate,
            scope: lexicalParent, context: &context)
        guard value.width == binding.type.width else {
            throw try failure(initial, "SV_SCOPE_ITERATION_WIDTH", "Frozen iteration value must have the declaration's exact width")
        }
        try context.observeBitWidth(UInt64(value.width.value))
        try context.charge(.workUnits, amount: UInt64(value.width.wordCount))
        guard value.isTwoState else {
            throw try failure(initial, "SV_SCOPE_ITERATION_BINARY", "A synthesis iteration value cannot contain X or Z")
        }
        for index in lexicalEntries.indices {
            try context.charge(.workUnits)
            if generate && lexicalEntries[index].symbol == binding.symbol &&
                lexicalEntries[index].declaration != binding.declaration {
                throw try failure(lexicalEntries[index].declaration, "SV_SCOPE_DUPLICATE_NAME", "A generated body redeclares its implicit genvar localparam")
            }
            if lexicalEntries[index].declaration == binding.declaration {
                lexicalEntries[index] = binding.entry(value: copy value, frozen: true)
                return
            }
        }
        // External control declarations need one local overlay; the construction
        // reservation covers container + 1 entries, including this single binding.
        guard lexicalEntries.count < capacity else {
            throw .invalidModel("Loop binding capacity exhausted")
        }
        lexicalEntries.append(binding.entry(value: copy value, frozen: true))
    }
    private consuming func publishScope(defaults: SystemVerilogParameterDefaults, container: Int,
        parent: SystemVerilogConstantScope?, children: consuming [Int]) -> SystemVerilogConstantScope {
        SystemVerilogConstantScope(defaults: defaults, container: container, parent: parent,
            entries: lexicalEntries, children: children)
    }
}
