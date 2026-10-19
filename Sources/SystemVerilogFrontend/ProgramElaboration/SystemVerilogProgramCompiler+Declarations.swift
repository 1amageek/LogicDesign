import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogProgramCompiler {
    borrowing func declarationSemantics(_ declaration: Int, typeNode: Int?, syntax: borrowing SystemVerilogSyntaxTree)
        throws(LogicKernelError) -> (domain: RTLResolvedSignal.ValueDomain, storage: RTLResolvedSignal.StorageKind) {
        var domain = RTLResolvedSignal.ValueDomain.fourState
        var explicitStorage = SystemVerilogSyntaxNode.Storage.unspecified
        var explicitBase = false
        if let typeNode, case .type(let base, _, _, let storage, let explicit) = try syntax.node(at: typeNode).kind {
            domain = base == .bit || base == .int ? .twoState : .fourState
            explicitStorage = storage; explicitBase = explicit
        }
        let storage: RTLResolvedSignal.StorageKind
        switch try syntax.node(at: declaration).kind {
        case .declaration(.net, _, _, _): storage = .net
        case .declaration(.variable, _, _, _): storage = .variable
        case .port(let direction, _, _, _):
            storage = explicitStorage == .variable || (explicitStorage != .net && direction == .output && explicitBase) ? .variable : .net
        default: throw .invalidModel("Runtime declaration has no signal semantics")
        }
        guard storage != .net || domain == .fourState else {
            throw try SystemVerilogConstantScope.failure(declaration, in: syntax, "SV_NET_DATA_TYPE", "Built-in nets require a four-state data type; use var for a two-state input")
        }
        return (domain, storage)
    }
}
