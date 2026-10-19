import LogicKernelCore

extension SystemVerilogParameterBinder {
    internal mutating func bindDeclaration(_ declaration: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        guard case .declaration(_, _, let type, let initial) = try syntax.node(at: declaration).kind,
              let initial else { throw .invalidModel("Parameter declaration has no initializer") }
        try enqueue(initial, parent: declaration, context: &context)
        if let type { try enqueue(type, parent: declaration, context: &context) }
        while let index = pending.popLast() {
            try context.charge(.workUnits)
            if visited[index] != 0 { continue }
            visited[index] = 1
            let node = try syntax.node(at: index)
            switch node.kind {
            case .identifier(let name):
                guard symbols.indices.contains(name) else { throw .invalidModel("Reference is outside the syntax symbol table") }
                let target = symbols[name]
                guard target >= 0 else {
                    throw try failure("SV_PARAMETER_UNRESOLVED_NAME", at: index, "Name is not a module-local parameter")
                }
                guard target != declaration else {
                    throw try failure("SV_PARAMETER_SELF_REFERENCE", at: index, "Parameter depends on its own definition")
                }
                guard try syntax.node(at: target).byteRange.lowerBound < node.byteRange.lowerBound else {
                    throw try failure("SV_PARAMETER_BEFORE_DECLARATION", at: index, "Parameter is referenced before its declaration")
                }
                try context.charge(.edges)
                references[index] = target
            case .literal: break
            case .unary(_, let operand), .signedCast(_, let operand):
                try enqueue(operand, parent: index, context: &context)
            case .binary(_, let left, let right), .repeated(let left, let right), .packedRange(let left, let right):
                try enqueue(right, parent: index, context: &context)
                try enqueue(left, parent: index, context: &context)
            case .conditional(let condition, let then, let elseBody):
                try enqueue(elseBody, parent: index, context: &context)
                try enqueue(then, parent: index, context: &context)
                try enqueue(condition, parent: index, context: &context)
            case .select(_, let value, let first, let second):
                if let second { try enqueue(second, parent: index, context: &context) }
                try enqueue(first, parent: index, context: &context)
                try enqueue(value, parent: index, context: &context)
            case .concatenate(let operands), .type(_, _, let operands, _, _):
                try enqueue(operands, parent: index, context: &context)
            default:
                throw try failure("SV_PARAMETER_NON_CONSTANT_SYNTAX", at: index, "Expected a parameter type or constant expression")
            }
        }
    }
}
