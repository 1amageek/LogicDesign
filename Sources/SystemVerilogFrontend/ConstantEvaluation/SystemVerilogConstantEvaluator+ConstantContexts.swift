import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogConstantEvaluator {
    internal borrowing func requireConstantSyntax(_ root: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        let scratch = try context.reserveStorage(byteCount: Self.bytes(syntax.nodeCount, MemoryLayout<Int>.stride))
        do throws(LogicKernelError) {
            var pending: [Int] = []; pending.reserveCapacity(syntax.nodeCount); pending.append(root)
            while let node = pending.popLast() {
                try context.charge(.workUnits)
                let kind = try syntax.node(at: node).kind
                if case .identifier(let name) = kind {
                    var entry: SystemVerilogScopeEntry?
                    if let signalScope { entry = try signalScope.constants.lookup(name, context: &context) }
                    else {
                        for local in lexicalEntries {
                            try context.charge(.workUnits)
                            if local.symbol == name { entry = local; break }
                        }
                        if entry == nil, let lexicalParent { entry = try lexicalParent.lookup(name, context: &context) }
                    }
                    if let entry, !entry.isGenerateConstant {
                        switch try syntax.node(at: entry.declaration).kind {
                        case .declaration(.parameter, _, _, _), .declaration(.localParameter, _, _, _): break
                        default:
                            let code = entry.value == nil ? "SV_SCOPE_NONCONSTANT_NAME" : "SV_LANGUAGE_CONSTANT_REQUIRED"
                            throw try failure(node, code, "A procedural variable cannot be used as a language constant")
                        }
                    }
                }
                for index in 0..<(try operandCount(kind)) {
                    guard pending.count < syntax.nodeCount else { throw .invalidModel("Constant-context traversal capacity exhausted") }
                    pending.append(try operand(kind, at: index))
                }
            }
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
    }
}
