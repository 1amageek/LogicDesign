import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogProgramCompiler {
    static func sameName(_ lhs: Int, syntax a: borrowing SystemVerilogSyntaxTree,
        _ rhs: Int, syntax b: borrowing SystemVerilogSyntaxTree, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        let first = try a.symbolRange(at: lhs); let second = try b.symbolRange(at: rhs)
        try context.charge(.workUnits, amount: UInt64(first.count) + 1)
        guard first.count == second.count else { return false }
        return a.source.withBytes { left in b.source.withBytes { right in
            for index in 0..<first.count where left[first.lowerBound + index] != right[second.lowerBound + index] { return false }
            return true
        } }
    }
    static func spelling(_ name: Int, syntax: borrowing SystemVerilogSyntaxTree,
        context: inout LogicKernelContext) throws(LogicKernelError) -> String {
        let range = try syntax.symbolRange(at: name)
        try context.charge(.workUnits, amount: UInt64(range.count))
        _ = try context.reserveStorage(byteCount: UInt64(range.count))
        // Names are materialized only at module selection and public port boundaries.
        // The retained source owns this read-only borrow; String consumes bytes synchronously.
        // Span is not Collection at the macOS 26 baseline, so the scoped buffer is used
        // only for the required public UTF-8 conversion. No pointer escapes.
        return syntax.source.withBytes { bytes in
            bytes.withUnsafeBufferPointer { buffer in String(decoding: buffer[range], as: UTF8.self) }
        }
    }
    borrowing func validateModules(top: String, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Module {
        var selected: Module?
        for tree in trees.indices {
            let syntax = trees[tree]
            for offset in syntax.modules {
                let node = try syntax.child(at: offset)
                guard case .module(let name, _, _, _, _) = try syntax.node(at: node).kind else { throw .invalidModel("Non-module root") }
                for earlierTree in 0...tree {
                    let earlier = trees[earlierTree]
                    for earlierOffset in earlier.modules {
                        try context.charge(.workUnits)
                        if earlierTree == tree && earlierOffset >= offset { break }
                        let earlierNode = try earlier.child(at: earlierOffset)
                        guard case .module(let earlierName, _, _, _, _) = try earlier.node(at: earlierNode).kind else { throw .invalidModel("Non-module root") }
                        if try Self.sameName(name, syntax: syntax, earlierName, syntax: earlier, context: &context) {
                            throw try SystemVerilogConstantScope.failure(node, in: syntax, "SV_MODULE_DUPLICATE", "Module name is not unique in the source bundle")
                        }
                    }
                }
                let range = try syntax.symbolRange(at: name)
                try context.charge(.workUnits, amount: UInt64(range.count) + 1)
                let matches = syntax.source.withBytes { bytes in
                    guard range.count == top.utf8.count else { return false }
                    var iterator = top.utf8.makeIterator()
                    for index in range { if bytes[index] != iterator.next() { return false } }
                    return true
                }
                if matches { selected = Module(tree: tree, node: node) }
            }
        }
        guard let selected else { throw .invalidInput("Requested top module is absent from the source bundle") }
        return selected
    }
    borrowing func findModule(_ name: Int, in syntax: borrowing SystemVerilogSyntaxTree,
        at node: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Module {
        for tree in trees.indices {
            for offset in trees[tree].modules {
                try context.charge(.workUnits)
                let candidate = try trees[tree].child(at: offset)
                guard case .module(let moduleName, _, _, _, _) = try trees[tree].node(at: candidate).kind else { throw .invalidModel("Non-module root") }
                if try Self.sameName(name, syntax: syntax, moduleName, syntax: trees[tree], context: &context) { return Module(tree: tree, node: candidate) }
            }
        }
        throw try SystemVerilogConstantScope.failure(node, in: syntax, "SV_MODULE_UNRESOLVED", "Instantiated module is absent from the source bundle")
    }
    mutating func module(_ selected: Module, defaults: SystemVerilogParameterDefaults,
        parent: SystemVerilogSignalScope?, instance: Int?, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogSignalScope {
        let syntax = trees[selected.tree]
        try enter(selected.node, syntax: syntax, context: &context); defer { depth -= 1 }
        for previous in ancestry {
            try context.charge(.workUnits)
            guard previous != selected else {
                throw try SystemVerilogConstantScope.failure(selected.node, in: syntax, "SV_MODULE_RECURSION", "Recursive module instantiation is outside the finite hierarchy profile")
            }
        }
        ancestry.append(selected); defer { ancestry.removeLast() }
        let constants = try SystemVerilogConstantScope.module(defaults, context: &context)
        let namespace = try namespace(context: &context)
        let ports = try portDeclarations(constants, context: &context)
        let connections = try matchPorts(ports, child: syntax, parent: parent, instance: instance, context: &context)
        let scope = try bindScope(constants, parent: nil, namespace: namespace, top: parent == nil,
            ports: ports, connections: connections, connectionScope: parent, context: &context)
        for connection in connections {
            let port = connection.port
            let child = try runtimeBinding(port.name, in: scope, context: &context)
            guard let child else { throw .invalidModel("Unbound elaborated port") }
            if parent == nil {
                let name = try Self.spelling(port.name, syntax: syntax, context: &context)
                try builder.addPort(RTLResolvedPort(id: id(), name: name,
                    direction: port.direction == .input ? .input : .output, signal: child.signal), context: &context)
                continue
            }
            guard let parent else { throw .invalidModel("Missing instance parent") }
            if port.direction == .input {
                if let actual = connection.actual {
                    if try inputAlias(actual, in: parent, type: child.type, context: &context) == child.signal { continue }
                    let rhs = try expression(actual, scope: parent, width: child.type.width.value, context: &context)
                    let assignment = try assign(child.signal, range: 0..<child.type.width.value, value: rhs.index,
                        timing: .blocking, node: actual, scope: parent, context: &context)
                    try addProcess(.continuous, body: assignment, node: actual, scope: parent, context: &context)
                } else if let initial = port.initial {
                    let rhs = try expression(initial, scope: scope, width: child.type.width.value, context: &context)
                    let assignment = try assign(child.signal, range: 0..<child.type.width.value, value: rhs.index,
                        timing: .blocking, node: initial, scope: scope, context: &context)
                    try addProcess(.continuous, body: assignment, node: initial, scope: scope, context: &context)
                } else { throw try Self.failure(port.declaration, scope: scope, "SV_PORT_UNCONNECTED_INPUT", "Input port has no connection or default") }
            } else if let actual = connection.actual {
                let rhs = try emit(.read(child.signal), type: WordLogicType(width: child.type.width, isSigned: child.type.isSigned),
                    node: port.declaration, scope: scope, context: &context)
                var destination = parent
                let assignment = try assignment(target: actual, rhs: rhs, timing: .blocking, scope: &destination,
                    namespace: namespace, procedural: false, context: &context)
                try addProcess(.continuous, body: assignment, node: actual, scope: parent, context: &context)
            }
        }
        guard case .module(_, _, _, let items, _) = try syntax.node(at: selected.node).kind else { throw .invalidModel("Lost module syntax") }
        try moduleItems(items, scope: scope, namespace: namespace, context: &context)
        return scope
    }
    mutating func moduleItems(_ items: Range<Int>, scope: borrowing SystemVerilogSignalScope,
        namespace: UInt64, context: inout LogicKernelContext) throws(LogicKernelError) {
        let syntax = scope.constants.defaults.bindings.syntax
        for offset in items { try moduleItem(syntax.child(at: offset), scope: scope, namespace: namespace, context: &context) }
    }
    mutating func moduleItem(_ node: Int, scope: borrowing SystemVerilogSignalScope,
        namespace: UInt64, context: inout LogicKernelContext) throws(LogicKernelError) {
        let syntax = scope.constants.defaults.bindings.syntax
        try enter(node, syntax: syntax, context: &context); defer { depth -= 1 }
        switch try syntax.node(at: node).kind {
        case .group(let items), .generateRegion(let items): try moduleItems(items, scope: scope, namespace: namespace, context: &context)
        case .declaration(.net, let name, _, let initial?):
            guard let signal = try runtimeBinding(name, in: scope, context: &context) else { throw .invalidModel("Missing net initializer target") }
            let rhs = try expression(initial, scope: scope, width: signal.type.width.value, context: &context)
            let body = try assign(signal.signal, range: 0..<signal.type.width.value, value: rhs.index, timing: .blocking, node: node, scope: scope, context: &context)
            try addProcess(.continuous, body: body, node: node, scope: scope, context: &context)
        case .declaration, .port, .empty: break
        case .process(let kind, let sensitivity, let body):
            var local = copy scope
            let control = try processControl(kind, sensitivity: sensitivity, body: body, scope: scope, context: &context)
            let statement = try statement(body, scope: &local, namespace: namespace, procedural: kind != .continuous, context: &context)
            try addProcess(control, body: statement, node: node, scope: scope, context: &context)
        case .instance(let name, _, _, _):
            let selected = try findModule(name, in: syntax, at: node, context: &context)
            let binding = try SystemVerilogParameterBinder.bind(trees[selected.tree], module: selected.node, context: &context)
            let defaults = try SystemVerilogInstanceParameterResolver.evaluate(instance: node, in: scope.constants, child: binding, context: &context)
            _ = try module(selected, defaults: defaults, parent: copy scope, instance: node, context: &context)
        case .generateBlock(_, let items):
            let constants = try scope.constants.entering(node, context: &context)
            let child = try bindScope(constants, parent: copy scope, namespace: namespace, context: &context)
            try moduleItems(items, scope: child, namespace: namespace, context: &context)
        case .generateIf, .generateCase:
            if let selected = try SystemVerilogGenerateSelector.select(node, in: scope.constants, context: &context) {
                if try scope.constants.owns(selected, context: &context) {
                    try moduleItem(selected, scope: scope, namespace: namespace, context: &context)
                } else if case .generateBlock = try syntax.node(at: selected).kind {
                    try moduleItem(selected, scope: scope, namespace: namespace, context: &context)
                } else {
                    let constants = try scope.constants.entering(selected, context: &context)
                    let child = try bindScope(constants, parent: copy scope, namespace: namespace, context: &context)
                    try moduleItem(selected, scope: child, namespace: namespace, context: &context)
                }
            }
        case .generateFor:
            var control = try SystemVerilogStaticLoop.prepare(node, in: scope.constants, context: &context)
            var iteration = try control.begin(context: &context)
            while let current = iteration {
                let selectedNamespace = try self.namespace(context: &context)
                let child = try bindScope(current.scope, parent: copy scope, namespace: selectedNamespace, context: &context)
                try moduleItem(current.body, scope: child, namespace: selectedNamespace, context: &context)
                iteration = try control.resume(afterBody: current, value: current.value, context: &context)
            }
        default: throw try Self.failure(node, scope: scope, "SV_MODULE_ITEM", "Syntax is not an admitted module item")
        }
    }
}
