import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogProgramCompiler {
    borrowing func portDeclarations(_ scope: borrowing SystemVerilogConstantScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> [Port] {
        let syntax = scope.defaults.bindings.syntax
        guard case .module(_, _, let headers, _, _) = try syntax.node(at: scope.container).kind else { throw .invalidModel("Ports require a module scope") }
        _ = try context.reserveStorage(byteCount: try SystemVerilogConstantEvaluator.bytes(headers.count, MemoryLayout<Port>.stride))
        var result: [Port] = []; result.reserveCapacity(headers.count)
        for offset in headers {
            let header = try syntax.child(at: offset)
            guard case .port(let direction, let name, _, let initial) = try syntax.node(at: header).kind else { throw .invalidModel("Malformed port header") }
            var declaration = header; var selectedDirection = direction; var selectedInitial = initial
            if direction == nil {
                for entry in scope.storage.entries {
                    try context.charge(.workUnits)
                    if entry.symbol == name, case .port(let bodyDirection?, _, _, let bodyInitial) = try syntax.node(at: entry.declaration).kind {
                        declaration = entry.declaration; selectedDirection = bodyDirection; selectedInitial = bodyInitial
                    }
                }
            }
            guard let selectedDirection else {
                throw try SystemVerilogConstantScope.failure(header, in: syntax, "SV_PORT_DIRECTION", "Non-ANSI port has no body direction declaration")
            }
            guard selectedDirection != .inoutPort else {
                throw try SystemVerilogConstantScope.failure(declaration, in: syntax, "SV_PORT_INOUT", "Inout resolution is outside the binary single-driver profile")
            }
            result.append(Port(name: name, declaration: declaration, direction: selectedDirection, initial: selectedInitial))
        }
        for entry in scope.storage.entries {
            try context.charge(.workUnits)
            guard case .port = try syntax.node(at: entry.declaration).kind else { continue }
            try context.charge(.workUnits, amount: UInt64(result.count))
            guard result.contains(where: { $0.name == entry.symbol }) else {
                throw try SystemVerilogConstantScope.failure(entry.declaration, in: syntax, "SV_PORT_NOT_IN_HEADER", "Body port is absent from the module header")
            }
        }
        return result
    }
    borrowing func matchPorts(_ ports: borrowing [Port], child: borrowing SystemVerilogSyntaxTree,
        parent: SystemVerilogSignalScope?, instance: Int?, context: inout LogicKernelContext)
        throws(LogicKernelError) -> [Connection] {
        _ = try context.reserveStorage(byteCount: try SystemVerilogConstantEvaluator.bytes(ports.count,
            MemoryLayout<Connection>.stride + MemoryLayout<Bool>.stride))
        var result: [Connection] = []; result.reserveCapacity(ports.count)
        for index in ports.indices { result.append(Connection(port: ports[index], actual: nil)) }
        guard let parent, let instance else { return result }
        let syntax = parent.constants.defaults.bindings.syntax
        guard case .instance(_, _, _, let actuals) = try syntax.node(at: instance).kind else { throw .invalidModel("Missing instance connections") }
        var seen = [Bool](repeating: false, count: ports.count)
        var named: Bool?; var ordinal = 0
        for offset in actuals {
            try context.charge(.workUnits)
            let node = try syntax.child(at: offset)
            guard case .binding(let name, let value) = try syntax.node(at: node).kind else { throw .invalidModel("Malformed port connection") }
            if let named, named != (name != nil) {
                throw try Self.failure(node, scope: parent, "SV_PORT_MIXED_BINDINGS", "Named and ordered port connections cannot be mixed")
            }
            named = name != nil
            let index: Int
            if let name {
                var found: Int?
                for candidate in ports.indices {
                    if try Self.sameName(name, syntax: syntax, ports[candidate].name, syntax: child, context: &context) { found = candidate; break }
                }
                guard let found else { throw try Self.failure(node, scope: parent, "SV_PORT_UNKNOWN", "Named port is absent from the child module") }
                index = found
            } else {
                guard ordinal < ports.count else { throw try Self.failure(node, scope: parent, "SV_PORT_EXCESS", "Too many ordered port connections") }
                index = ordinal; ordinal += 1
            }
            guard !seen[index] else { throw try Self.failure(node, scope: parent, "SV_PORT_DUPLICATE", "Port has more than one connection") }
            seen[index] = true; result[index] = Connection(port: ports[index], actual: value)
        }
        return result
    }
    borrowing func inputAlias(_ node: Int, in scope: borrowing SystemVerilogSignalScope,
        type: SystemVerilogConstantType, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLSignalIndex? {
        guard case .identifier(let name) = try scope.constants.defaults.bindings.syntax.node(at: node).kind else { return nil }
        let resolved = try scope.resolve(name, reference: node, context: &context)
        guard resolved.type.width == type.width, resolved.type.isSigned == type.isSigned else { return nil }
        return resolved.signal
    }
    mutating func bindScope(_ constants: SystemVerilogConstantScope, parent: SystemVerilogSignalScope?,
        namespace: UInt64, top: Bool = false, ports: [Port] = [], connections: [Connection] = [],
        connectionScope: SystemVerilogSignalScope? = nil, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogSignalScope {
        let syntax = constants.defaults.bindings.syntax
        let count = constants.storage.entries.count
        let scratch = try context.reserveStorage(byteCount: try SystemVerilogConstantEvaluator.bytes(count, MemoryLayout<SystemVerilogSignalBinding>.stride))
        let result: SystemVerilogSignalScope
        do throws(LogicKernelError) {
            var bindings: [SystemVerilogSignalBinding] = []; bindings.reserveCapacity(count)
            for entry in constants.storage.entries {
                try context.charge(.workUnits)
                guard entry.value == nil else { continue }
                let declaration: Int; let typeNode: Int?; let initial: Int?; let port: Port?
                switch try syntax.node(at: entry.declaration).kind {
                case .declaration(.variable, _, let type, let value): declaration = entry.declaration; typeNode = type; initial = value; port = nil
                case .declaration(.net, _, let type, _): declaration = entry.declaration; typeNode = type; initial = nil; port = nil
                case .port:
                    try context.charge(.workUnits, amount: UInt64(ports.count + bindings.count))
                    guard let matched = ports.first(where: { $0.name == entry.symbol }) else { throw .invalidModel("Unmatched port declaration") }
                    if bindings.contains(where: { $0.declaration == matched.declaration }) { continue }
                    declaration = matched.declaration; port = matched
                    guard case .port(_, _, let type, let value) = try syntax.node(at: declaration).kind else { throw .invalidModel("Lost port declaration") }
                    typeNode = type; initial = matched.direction == .output ? value : nil
                default: continue
                }
                let type = try SystemVerilogConstantEvaluator.withExpressionWorkspace(constants.defaults, scope: constants, context: &context) {
                    (evaluator, context) throws(LogicKernelError) in
                    try evaluator.declarationType(typeNode, inferred: nil, context: &context)
                }
                try context.charge(.workUnits, amount: UInt64(connections.count))
                if let port, port.direction == .input, let connectionScope,
                   let actual = connections.first(where: { $0.port.name == port.name })?.actual,
                   let alias = try inputAlias(actual, in: connectionScope, type: type, context: &context) {
                    bindings.append(SystemVerilogSignalBinding(declaration: declaration, type: type, signal: alias)); continue
                }
                var reused: SystemVerilogSignalBinding?
                for record in signals {
                    try context.charge(.workUnits)
                    if record.namespace == namespace && record.declaration == declaration { reused = record.binding; break }
                }
                if let reused {
                    guard reused.type.width == type.width, reused.type.isSigned == type.isSigned,
                          reused.type.dimensions == type.dimensions else {
                        throw try SystemVerilogConstantScope.failure(declaration, in: syntax, "SV_PROCEDURAL_DECLARATION_TYPE", "A reused procedural declaration cannot change type during unrolling")
                    }
                    bindings.append(reused); continue
                }
                let value: LogicFourStateVector?
                if let initial {
                    try SystemVerilogConstantEvaluator.withExpressionWorkspace(constants.defaults, scope: constants, context: &context) {
                        (evaluator, context) throws(LogicKernelError) in try evaluator.requireConstantSyntax(initial, context: &context)
                    }
                    let expression = try SystemVerilogConstantExpression.prepare(node: initial, in: constants, context: &context)
                    value = try expression.evaluate(width: type.width.value, context: &context)
                } else { value = nil }
                let signal = try builder.addSignal(RTLResolvedSignal(id: id(), type: WordLogicType(width: type.width, isSigned: type.isSigned),
                    isInput: top && port?.direction == .input, initialValue: value,
                    origin: Self.origin(declaration, syntax: syntax)), context: &context)
                let binding = SystemVerilogSignalBinding(declaration: declaration, type: type, signal: signal)
                guard signals.count < capacity.signals else { throw .invalidInput("Program signal cache capacity exhausted") }
                signals.append(Signal(namespace: namespace, declaration: declaration, binding: binding)); bindings.append(binding)
            }
            result = try SystemVerilogSignalScope.bind(constants, parent: parent, signals: bindings, context: &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }
    borrowing func runtimeBinding(_ name: Int, in scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogSignalBinding? {
        guard let nearest = try scope.constants.lookup(name, context: &context) else { return nil }
        var current: SystemVerilogSignalScope? = copy scope
        while let local = current {
            for binding in local.storage.bindings {
                try context.charge(.workUnits)
                if binding.declaration == nearest.declaration { return binding }
                try context.charge(.workUnits, amount: UInt64(local.constants.storage.entries.count))
                // A non-ANSI header and its body denote the same signal in this exact scope.
                if local.constants.storage.entries.contains(where: { $0.declaration == nearest.declaration }),
                   case .port(_, let symbol, _, _) = try local.constants.defaults.bindings.syntax.node(at: binding.declaration).kind,
                   symbol == name { return binding }
            }
            current = local.storage.parent
        }
        return nil
    }
}
