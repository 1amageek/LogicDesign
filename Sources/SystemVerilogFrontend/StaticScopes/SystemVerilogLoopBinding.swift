import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
internal struct SystemVerilogLoopBinding: Sendable {
    let isGenerate: Bool
    let declaration: Int
    let symbol: Int
    let initializer: Int
    let type: SystemVerilogConstantType
    let origin: LogicKernelSourceRange

    static func resolve(initial: Int, generate: Bool, scope: borrowing SystemVerilogConstantScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        let syntax = scope.defaults.bindings.syntax
        let declaration: Int; let symbol: Int; let expression: Int
        switch try syntax.node(at: initial).kind {
        case .declaration(_, let name, _, let value?):
            declaration = initial; symbol = name; expression = value
        case .assignment(.blocking, let target, let value?):
            guard case .identifier(let name) = try syntax.node(at: target).kind,
                  let entry = try scope.lookup(name, context: &context) else {
                throw try SystemVerilogConstantScope.failure(initial, in: syntax, "SV_LOOP_TARGET", "Loop initialization requires a declared integral variable")
            }
            guard !entry.isGenerateConstant else {
                throw try SystemVerilogConstantScope.failure(initial, in: syntax, "SV_LOOP_CONSTANT_TARGET", "An implicit generate localparam is not an assignable genvar")
            }
            declaration = entry.declaration; symbol = name; expression = value
        default:
            throw try SystemVerilogConstantScope.failure(initial, in: syntax, "SV_LOOP_INITIALIZER", "Loop initialization requires one blocking assignment or declaration")
        }
        guard case .declaration(let kind, _, let typeNode, _) = try syntax.node(at: declaration).kind,
              generate ? kind == .genvar : kind == .variable else {
            throw try SystemVerilogConstantScope.failure(initial, in: syntax, "SV_LOOP_VARIABLE_KIND", "Generate loops require genvar; procedural loops require an integral variable")
        }
        let type = try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.defaults, scope: copy scope, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            if kind == .genvar { return try SystemVerilogConstantType(width: 32, signed: true) }
            guard let typeNode else {
                throw try evaluator.failure(declaration, "SV_LOOP_EXPLICIT_TYPE", "A static procedural control requires an explicit integral type")
            }
            return try evaluator.declarationType(typeNode, inferred: nil, context: &context)
        }
        let range = try syntax.node(at: declaration).byteRange
        let origin = try syntax.source.origin(for: range)
        return Self(isGenerate: generate, declaration: declaration, symbol: symbol, initializer: expression, type: type, origin: origin)
    }
    borrowing func entry(value: LogicFourStateVector?, frozen: Bool = false) -> SystemVerilogScopeEntry {
        SystemVerilogScopeEntry(symbol: symbol, declaration: declaration,
            value: value.map { SystemVerilogConstant(type: type, value: $0, origin: origin) },
            isGenerateConstant: frozen && isGenerate)
    }
    borrowing func validate(_ value: borrowing LogicFourStateVector, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        try context.observeBitWidth(UInt64(value.width.value))
        try context.charge(.workUnits, amount: UInt64(value.width.wordCount))
        guard value.width == type.width, value.isTwoState else {
            throw .invalidInput("Loop body value must be binary and have the control declaration's exact width")
        }
    }
}
