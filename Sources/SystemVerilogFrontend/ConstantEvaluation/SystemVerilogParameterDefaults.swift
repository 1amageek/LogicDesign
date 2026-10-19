import LogicKernelCore

package struct SystemVerilogParameterDefaults: Sendable {
    private final class Storage: Sendable {
        let values: [SystemVerilogConstant?]
        init(_ values: consuming [SystemVerilogConstant?]) { self.values = values }
    }
    package let bindings: SystemVerilogParameterBindings
    private let storage: Storage
    internal init(bindings: SystemVerilogParameterBindings, values: consuming [SystemVerilogConstant?]) {
        self.bindings = bindings; storage = Storage(values)
    }
    internal var valuesForEvaluation: [SystemVerilogConstant?] { storage.values }
    package borrowing func value(forDeclaration node: Int) throws(LogicKernelError) -> SystemVerilogConstant {
        guard storage.values.indices.contains(node), let value = storage.values[node] else {
            throw .invalidInput("Node is not an evaluated parameter declaration")
        }
        return value
    }
    @available(macOS 26.0, *)
    package borrowing func withValues<Result, Failure: Error>(
        _ body: (borrowing Span<SystemVerilogConstant?>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let values = owner.values
        defer { withExtendedLifetime(owner) {} }
        return try body(values.isEmpty ? Span() : values.span)
    }
}
