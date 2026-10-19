import LogicKernelCore

package struct SystemVerilogParameterBindings: Sendable {
    private final class Storage: Sendable {
        let declarations: [Int]
        let references: [Int]
        let symbols: [Int]
        init(declarations: consuming [Int], references: consuming [Int], symbols: consuming [Int]) {
            self.declarations = declarations; self.references = references; self.symbols = symbols
        }
    }
    package let syntax: SystemVerilogSyntaxTree
    package let module: Int
    private let storage: Storage
    package var count: Int { storage.declarations.count }

    internal init(syntax: SystemVerilogSyntaxTree, module: Int, declarations: consuming [Int],
                  references: consuming [Int], symbols: consuming [Int]) {
        self.syntax = syntax; self.module = module
        storage = Storage(declarations: declarations, references: references, symbols: symbols)
    }

    internal borrowing func sharesScope(with other: borrowing Self) -> Bool { storage === other.storage }
    package borrowing func isOverridable(_ declaration: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        guard case .declaration(let kind, let name, _, _) = try syntax.node(at: declaration).kind,
              storage.symbols.indices.contains(name), storage.symbols[name] == declaration else {
            throw .invalidInput("Declaration is not in the parameter binding owner")
        }
        guard kind == .parameter else { return false }
        guard case .module(_, let parameters, _, _, let hasParameterPortList) = try syntax.node(at: module).kind else {
            throw .invalidModel("Parameter bindings lost their module")
        }
        if !hasParameterPortList { return true }
        for offset in parameters {
            try context.charge(.workUnits)
            if try syntax.child(at: offset) == declaration { return true }
        }
        return false
    }
    package borrowing func declaration(at index: Int) throws(LogicKernelError) -> Int {
        guard storage.declarations.indices.contains(index) else { throw .invalidInput("Parameter ordinal outside bindings") }
        return storage.declarations[index]
    }
    package borrowing func declaration(named symbol: Int) throws(LogicKernelError) -> Int? {
        guard storage.symbols.indices.contains(symbol) else { throw .invalidInput("Parameter symbol outside syntax") }
        let declaration = storage.symbols[symbol]
        return declaration < 0 ? nil : declaration
    }
    package borrowing func declaration(forReference node: Int) throws(LogicKernelError) -> Int? {
        guard storage.references.indices.contains(node) else { throw .invalidInput("Parameter reference outside syntax") }
        let declaration = storage.references[node]
        return declaration < 0 ? nil : declaration
    }
    @available(macOS 26.0, *)
    package borrowing func withBindings<Result, Failure: Error>(
        _ body: (borrowing Span<Int>, borrowing Span<Int>, borrowing Span<Int>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let declarations = owner.declarations; let references = owner.references; let symbols = owner.symbols
        defer { withExtendedLifetime(owner) {} }
        return try body(declarations.isEmpty ? Span() : declarations.span,
                        references.isEmpty ? Span() : references.span, symbols.isEmpty ? Span() : symbols.span)
    }
}
