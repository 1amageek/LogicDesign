import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
package struct SystemVerilogStaticLoop: ~Copyable {
    private enum Phase { case prepared, yielded, finished, failed }
    private var parent: SystemVerilogConstantScope
    private let node: Int
    private let condition: Int
    private let step: Int
    private let body: Int
    private let binding: SystemVerilogLoopBinding
    private var phase: Phase = .prepared
    private var identity: SystemVerilogLoopIteration.Identity?
    package private(set) var finalValue: LogicFourStateVector?

    package static func prepare(_ node: Int, in scope: borrowing SystemVerilogConstantScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try scope.requireChild(node, context: &context)
        let initial: Int; let condition: Int; let step: Int; let body: Int; let generate: Bool
        let syntax = scope.defaults.bindings.syntax
        switch try syntax.node(at: node).kind {
        case .generateFor(let i, let c, let s, let b):
            initial = i; condition = c; step = s; body = b; generate = true
        case .forStatement(let i, let c, let s, let b):
            initial = i; condition = c; step = s; body = b; generate = false
        default: throw .invalidInput("Static control requires a for loop")
        }
        let binding = try SystemVerilogLoopBinding.resolve(initial: initial, generate: generate, scope: scope, context: &context)
        guard case .assignment(let operation, let target, _) = try syntax.node(at: step).kind,
              operation != .nonBlocking, case .identifier(let symbol) = try syntax.node(at: target).kind,
              symbol == binding.symbol else {
            throw try SystemVerilogConstantScope.failure(step, in: syntax, "SV_LOOP_STEP_TARGET", "Loop step must update its own control declaration")
        }
        return Self(parent: copy scope, node: node, condition: condition, step: step, body: body, binding: binding)
    }
    package mutating func begin(context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogLoopIteration? {
        guard phase == .prepared else { throw .invalidInput("Static loop has already begun") }
        phase = .failed
        let value = try SystemVerilogLoopControlEvaluation.initialize(binding, scope: parent, context: &context)
        return try advance(value, context: &context)
    }
    package mutating func resume(afterBody iteration: borrowing SystemVerilogLoopIteration,
        value: borrowing LogicFourStateVector, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogLoopIteration? {
        guard phase == .yielded, identity === iteration.identity else {
            throw .invalidInput("Loop resume requires its currently yielded iteration")
        }
        phase = .failed; identity = nil
        try binding.validate(value, context: &context)
        if binding.isGenerate {
            let unchanged = try value.equalsBinary(iteration.value, context: &context)
            guard unchanged else {
                throw try SystemVerilogConstantScope.failure(body, in: parent.defaults.bindings.syntax,
                    "SV_GENERATE_CONTROL_WRITE", "A generated body's implicit genvar localparam is immutable")
            }
        }
        let updated = try SystemVerilogLoopControlEvaluation.update(step, binding: binding,
            value: value, scope: parent, context: &context)
        return try advance(updated, context: &context)
    }
    internal mutating func refreshProceduralParent(_ updated: borrowing SystemVerilogConstantScope)
        throws(LogicKernelError) {
        guard !binding.isGenerate, phase == .yielded,
              updated.storage.identity === parent.storage.identity,
              updated.defaults.bindings.sharesScope(with: parent.defaults.bindings) else {
            throw .invalidInput("Loop parent replacement requires its exact procedural lexical owner")
        }
        parent = copy updated
    }
    private mutating func advance(_ value: borrowing LogicFourStateVector, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogLoopIteration? {
        let active = try SystemVerilogLoopControlEvaluation.condition(condition, binding: binding,
            value: value, scope: parent, context: &context)
        if !active { finalValue = copy value; phase = .finished; return nil }
        try context.charge(.expansion)
        let scope = try parent.iteration(of: node, value: value, context: &context)
        let token = SystemVerilogLoopIteration.Identity()
        identity = token; phase = .yielded
        return SystemVerilogLoopIteration(identity: token, body: body, declaration: binding.declaration,
            scope: scope, value: copy value)
    }
}
