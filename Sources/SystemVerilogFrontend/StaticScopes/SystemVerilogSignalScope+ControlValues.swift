import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogSignalScope {
    internal borrowing func frozenControl(_ declaration: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogConstant? {
        var current: Self? = copy self
        while let scope = current {
            for entry in scope.constants.storage.entries {
                try context.charge(.workUnits)
                if entry.declaration == declaration { return entry.value }
            }
            current = scope.storage.parent
        }
        return nil
    }
    internal borrowing func replacingControl(_ declaration: Int, with value: borrowing LogicFourStateVector,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        for index in constants.storage.entries.indices {
            try context.charge(.workUnits)
            let entry = constants.storage.entries[index]
            guard entry.declaration == declaration else { continue }
            guard !entry.isGenerateConstant, let old = entry.value,
                  case .declaration(.variable, _, _, _) = try constants.defaults.bindings.syntax.node(at: declaration).kind,
                  old.type.width == value.width, value.isTwoState else {
                throw try SystemVerilogConstantScope.failure(declaration, in: constants.defaults.bindings.syntax,
                    "SV_STATIC_CONTROL_WRITE", "Only an exactly typed frozen procedural control may be updated")
            }
            let bytes = try SystemVerilogConstantEvaluator.bytes(constants.storage.entries.count, MemoryLayout<SystemVerilogScopeEntry>.stride)
            _ = try context.reserveStorage(byteCount: bytes)
            var entries = constants.storage.entries
            entries[index].value = SystemVerilogConstant(type: old.type, value: copy value, origin: old.origin)
            let updated = SystemVerilogConstantScope(defaults: constants.defaults, container: constants.container,
                parent: constants.storage.parent, entries: entries, children: constants.storage.children, identity: constants.storage.identity)
            return Self(constants: updated, storage: Storage(parent: storage.parent, bindings: storage.bindings))
        }
        guard let parent = storage.parent else { throw .invalidInput("Frozen procedural control is not in the lexical chain") }
        let updatedParent = try parent.replacingControl(declaration, with: value, context: &context)
        let updated = SystemVerilogConstantScope(defaults: constants.defaults, container: constants.container,
            parent: updatedParent.constants, entries: constants.storage.entries, children: constants.storage.children, identity: constants.storage.identity)
        return Self(constants: updated, storage: Storage(parent: updatedParent, bindings: storage.bindings))
    }
    internal borrowing func sameControls(as other: borrowing Self, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        guard constants.storage.identity === other.constants.storage.identity else { throw .invalidInput("Control comparison requires one lexical owner") }
        var current: Self? = copy self
        while let scope = current {
            for entry in scope.constants.storage.entries {
                try context.charge(.workUnits)
                guard let value = entry.value, !entry.isGenerateConstant,
                      case .declaration(.variable, _, _, _) = try constants.defaults.bindings.syntax.node(at: entry.declaration).kind else { continue }
                guard let counterpart = try other.frozenControl(entry.declaration, context: &context),
                      try value.value.equalsBinary(counterpart.value, context: &context) else { return false }
            }
            current = scope.storage.parent
        }
        return true
    }
}
