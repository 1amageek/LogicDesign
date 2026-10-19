import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogProgramCompiler {
    mutating func addProcess(_ control: RTLResolvedProcess.Control, body: RTLStatementIndex,
        node: Int, scope: borrowing SystemVerilogSignalScope, context: inout LogicKernelContext) throws(LogicKernelError) {
        try builder.addProcess(RTLResolvedProcess(id: id(), control: control, body: body,
            origin: Self.origin(node, syntax: scope.constants.defaults.bindings.syntax)), context: &context)
    }
    mutating func controlRead(_ node: Int, in scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> (RTLSignalIndex, RTLExpressionIndex) {
        let syntax = scope.constants.defaults.bindings.syntax
        guard case .identifier(let name) = try syntax.node(at: node).kind else {
            throw try Self.failure(node, scope: scope, "SV_EVENT_SIGNAL", "Clock and asynchronous reset events require direct scalar signals")
        }
        let resolved = try scope.resolve(name, reference: node, context: &context)
        guard let signal = resolved.signal, resolved.type.width.value == 1 else {
            throw try Self.failure(node, scope: scope, "SV_EVENT_SCALAR", "Clock and asynchronous reset events require runtime scalar signals")
        }
        for control in controls {
            try context.charge(.workUnits)
            if control.signal == signal { return (signal, control.expression) }
        }
        let type = WordLogicType(width: resolved.type.width, isSigned: resolved.type.isSigned)
        var value = try emit(.read(signal), type: type, node: node, scope: scope, context: &context)
        if type.isSigned {
            value = try emit(.compute(.bitcast), type: WordLogicType(width: type.width), a: value.index, node: node, scope: scope, context: &context)
        }
        guard controls.count < capacity.signals else { throw .invalidInput("Canonical event cache capacity exhausted") }
        controls.append((signal, value.index)); return (signal, value.index)
    }
    mutating func resetTest(_ root: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> (signal: RTLSignalIndex, positive: Bool)? {
        let syntax = scope.constants.defaults.bindings.syntax
        var node = root; var positive = true
        while true {
            try context.charge(.workUnits)
            switch try syntax.node(at: node).kind {
            case .identifier(let name):
                let value = try scope.resolve(name, reference: node, context: &context)
                guard let signal = value.signal, value.type.width.value == 1 else { return nil }
                return (signal, positive)
            case .unary(.logicalNot, let operand), .unary(.invert, let operand): positive.toggle(); node = operand
            case .binary(let op, let left, let right) where op == .equal || op == .notEqual || op == .caseEqual || op == .caseNotEqual:
                let constants = try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.constants.defaults,
                    scope: scope.constants, signals: copy scope, context: &context) {
                    (evaluator, context) throws(LogicKernelError) -> (Int, Bool)? in
                    try evaluator.infer(left, context: &context); try evaluator.infer(right, context: &context)
                    let lhs = try evaluator.metadata(left); let rhs = try evaluator.metadata(right)
                    let constant: Int; let variable: Int
                    if !lhs.containsRuntime { constant = left; variable = right }
                    else if !rhs.containsRuntime { constant = right; variable = left }
                    else { return nil }
                    let type = try evaluator.metadata(constant).type
                    let value = try evaluator.evaluateExpression(constant, width: type.width.value, signed: type.isSigned, context: &context)
                    for bit in 1..<value.width.value {
                        try context.charge(.workUnits)
                        if try value.bit(at: bit) != .zero { return nil }
                    }
                    let one = try value.bit(at: 0) == .one
                    return (variable, one)
                }
                guard let constants else { return nil }
                if !constants.1 { positive.toggle() }
                if op == .notEqual || op == .caseNotEqual { positive.toggle() }
                node = constants.0
            default: return nil
            }
        }
    }
    mutating func processControl(_ kind: SystemVerilogSyntaxNode.Process, sensitivity: Int?, body: Int,
        scope: borrowing SystemVerilogSignalScope, context: inout LogicKernelContext)
        throws(LogicKernelError) -> RTLResolvedProcess.Control {
        switch kind {
        case .continuous: return .continuous
        case .combinational: return .combinational
        case .latch: return .latch
        case .initial: throw try Self.failure(body, scope: scope, "SV_INITIAL_PROCESS", "Initial processes are outside the initial synthesis profile; use explicit constant declaration initialization")
        case .always, .flipFlop: break
        }
        let syntax = scope.constants.defaults.bindings.syntax
        guard let sensitivity, case .sensitivity(let all, let terms) = try syntax.node(at: sensitivity).kind else { throw .invalidModel("Missing process sensitivity") }
        if all {
            guard kind == .always else { throw try Self.failure(sensitivity, scope: scope, "SV_FF_EDGE_REQUIRED", "always_ff requires a clock edge") }
            return .levelSensitive
        }
        guard (1...2).contains(terms.count) else {
            throw try Self.failure(sensitivity, scope: scope, "SV_EVENT_PROFILE", "FF profile admits one clock edge and at most one asynchronous reset edge")
        }
        var first: (signal: RTLSignalIndex, read: RTLExpressionIndex, edge: BitStateControl.Edge)?
        var second: (signal: RTLSignalIndex, read: RTLExpressionIndex, edge: BitStateControl.Edge)?
        for offset in terms {
            let event = try syntax.child(at: offset)
            guard case .event(let edge, let expression) = try syntax.node(at: event).kind, edge != .level else {
                throw try Self.failure(event, scope: scope, "SV_LEVEL_EVENT_PROFILE", "Ordinary combinational sensitivity must use @* in the initial profile")
            }
            let value = try controlRead(expression, in: scope, context: &context)
            let term = (value.0, value.1, edge == .rising ? BitStateControl.Edge.rising : .falling)
            if first == nil { first = term } else { second = term }
        }
        guard let first else { throw .invalidModel("Empty FF sensitivity") }
        guard let second else { return .flipFlop(clock: first.read, edge: first.edge, asynchronousReset: nil) }
        guard first.signal != second.signal else { throw try Self.failure(sensitivity, scope: scope, "SV_EVENT_DUPLICATE", "Clock and asynchronous reset must be distinct signals") }
        var dominant = body
        while case .block(_, let statements) = try syntax.node(at: dominant).kind, statements.count == 1 {
            try context.charge(.workUnits); dominant = try syntax.child(at: statements.lowerBound)
        }
        guard case .ifStatement(let condition, _, _) = try syntax.node(at: dominant).kind,
              let test = try resetTest(condition, scope: scope, context: &context) else {
            throw try Self.failure(body, scope: scope, "SV_RESET_DOMINANCE", "Asynchronous reset requires a dominant scalar polarity condition")
        }
        let reset: (signal: RTLSignalIndex, read: RTLExpressionIndex, edge: BitStateControl.Edge)
        let clock: (signal: RTLSignalIndex, read: RTLExpressionIndex, edge: BitStateControl.Edge)
        if test.signal == first.signal { reset = first; clock = second }
        else if test.signal == second.signal { reset = second; clock = first }
        else { throw try Self.failure(condition, scope: scope, "SV_RESET_EVENT", "Dominant reset condition is absent from the edge list") }
        guard (reset.edge == .rising) == test.positive else {
            throw try Self.failure(condition, scope: scope, "SV_RESET_EDGE_POLARITY", "Asynchronous reset edge must assert the dominant reset condition")
        }
        return .flipFlop(clock: clock.read, edge: clock.edge, asynchronousReset: RTLResolvedReset(signal: reset.read, activeHigh: test.positive))
    }
}
