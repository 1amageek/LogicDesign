import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
package struct SystemVerilogInstanceParameterResolver: ~Copyable {
    private let parent: SystemVerilogParameterDefaults
    private let child: SystemVerilogParameterBindings
    private var scope: SystemVerilogConstantScope? = nil
    private var seen: [UInt8]
    private var pending: [Int] = []
    private var overrides: [SystemVerilogParameterOverride] = []

    package static func evaluate(instance: Int, in parent: borrowing SystemVerilogParameterDefaults,
        child: borrowing SystemVerilogParameterBindings, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogParameterDefaults {
        try execute(instance: instance, in: parent, scope: nil, child: child, context: &context)
    }
    package static func evaluate(instance: Int, in scope: borrowing SystemVerilogConstantScope,
        child: borrowing SystemVerilogParameterBindings, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogParameterDefaults {
        guard try scope.owns(instance, context: &context) else {
            throw .invalidInput("Instance does not belong directly to the supplied lexical scope")
        }
        return try execute(instance: instance, in: scope.defaults, scope: copy scope, child: child, context: &context)
    }
    private static func execute(instance: Int, in parent: borrowing SystemVerilogParameterDefaults,
        scope: SystemVerilogConstantScope?, child: borrowing SystemVerilogParameterBindings,
        context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogParameterDefaults {
        try context.checkpoint()
        let syntax = parent.bindings.syntax
        guard case .instance(let moduleName, _, let assignments, _) = try syntax.node(at: instance).kind,
              case .module(let childName, _, _, _, _) = try child.syntax.node(at: child.module).kind else {
            throw .invalidInput("Instance parameter composition requires instance and module syntax")
        }
        let traversalBytes = try bytes(syntax.nodeCount, stride: MemoryLayout<Int>.stride)
        let targetBytes = try bytes(child.syntax.nodeCount, stride: MemoryLayout<UInt8>.stride)
        let handleBytes = try bytes(assignments.count, stride: MemoryLayout<SystemVerilogParameterOverride>.stride)
        let scratch = try context.reserveStorage(byteCount: sum(sum(traversalBytes, targetBytes), handleBytes))
        let result: SystemVerilogParameterDefaults
        do throws(LogicKernelError) {
            var resolver = Self(parent: copy parent, child: copy child, scope: scope,
                seen: [UInt8](repeating: 0, count: child.syntax.nodeCount))
            resolver.pending.reserveCapacity(syntax.nodeCount); resolver.overrides.reserveCapacity(assignments.count)
            if scope == nil {
                guard try resolver.isDirect(instance, context: &context) else {
                    throw .invalidInput("Instance is outside the supplied module-local parameter scope")
                }
            }
            guard try resolver.sameName(moduleName, in: syntax, childName, in: child.syntax, context: &context) else {
                throw .invalidInput("Supplied child module does not match the instance module name")
            }
            try resolver.match(assignments, context: &context)
            result = try SystemVerilogConstantEvaluator.evaluate(child, overrides: resolver.overrides, context: &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }
    private static func bytes(_ count: Int, stride: Int) throws(LogicKernelError) -> UInt64 {
        let value = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
        guard !value.overflow else { throw .invalidInput("Instance parameter storage overflow") }
        return value.partialValue
    }
    private static func sum(_ left: UInt64, _ right: UInt64) throws(LogicKernelError) -> UInt64 {
        let value = left.addingReportingOverflow(right)
        guard !value.overflow else { throw .invalidInput("Instance parameter storage overflow") }
        return value.partialValue
    }
    private borrowing func failure(_ node: Int, _ code: String, _ message: String)
        throws(LogicKernelError) -> LogicKernelError {
        let syntax = parent.bindings.syntax; let range = try syntax.node(at: node).byteRange
        return .sourceFailure(code: .trusted(code), source: try syntax.source.origin(for: range), message: message)
    }
    private mutating func isDirect(_ instance: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        let syntax = parent.bindings.syntax
        guard case .module(_, _, _, let items, _) = try syntax.node(at: parent.bindings.module).kind else {
            throw .invalidModel("Parent defaults lost their module")
        }
        for offset in items.reversed() { pending.append(try syntax.child(at: offset)) }
        while let node = pending.popLast() {
            try context.charge(.workUnits)
            if node == instance { return true }
            switch try syntax.node(at: node).kind {
            case .group(let children), .generateRegion(let children):
                guard children.count <= syntax.nodeCount - pending.count else {
                    throw .invalidModel("Instance scope traversal exceeds syntax capacity")
                }
                for offset in children.reversed() { pending.append(try syntax.child(at: offset)) }
            default: break
            }
        }
        return false
    }
    private borrowing func sameName(_ left: Int, in lhs: borrowing SystemVerilogSyntaxTree,
        _ right: Int, in rhs: borrowing SystemVerilogSyntaxTree, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        let first = try lhs.symbolRange(at: left); let second = try rhs.symbolRange(at: right)
        try context.charge(.workUnits, amount: UInt64(first.count) + 1)
        guard first.count == second.count else { return false }
        return lhs.source.withBytes { a in
            rhs.source.withBytes { b in
                for index in 0..<first.count { if a[first.lowerBound + index] != b[second.lowerBound + index] { return false } }
                return true
            }
        }
    }
    private mutating func match(_ assignments: Range<Int>, context: inout LogicKernelContext) throws(LogicKernelError) {
        let syntax = parent.bindings.syntax
        var named: Bool?
        var nextOrdinal = 0
        for offset in assignments {
            try context.charge(.workUnits)
            let assignment = try syntax.child(at: offset)
            guard case .binding(let name, let value) = try syntax.node(at: assignment).kind else {
                throw .invalidModel("Instance assignment list contains another syntax kind")
            }
            if let named, named != (name != nil) {
                throw try failure(assignment, "SV_PARAMETER_MIXED_ASSIGNMENTS", "Named and ordered parameter assignments cannot be mixed")
            }
            named = name != nil
            let target: Int
            if let name {
                var found: Int?
                for ordinal in 0..<child.count {
                    try context.charge(.workUnits)
                    let declaration = try child.declaration(at: ordinal)
                    guard case .declaration(_, let childName, _, _) = try child.syntax.node(at: declaration).kind else {
                        throw .invalidModel("Child parameter bindings contain another syntax kind")
                    }
                    if try sameName(name, in: syntax, childName, in: child.syntax, context: &context) { found = declaration; break }
                }
                guard let found else { throw try failure(assignment, "SV_PARAMETER_UNKNOWN_OVERRIDE", "Named parameter does not exist in the child module") }
                guard try child.isOverridable(found, context: &context) else {
                    throw try failure(assignment, "SV_PARAMETER_LOCAL_OVERRIDE", "A local parameter cannot be overridden")
                }
                target = found
            } else {
                var found: Int?
                while nextOrdinal < child.count {
                    try context.charge(.workUnits)
                    let declaration = try child.declaration(at: nextOrdinal); nextOrdinal += 1
                    if try child.isOverridable(declaration, context: &context) { found = declaration; break }
                }
                guard let found else { throw try failure(assignment, "SV_PARAMETER_EXCESS_ASSIGNMENTS", "Too many ordered parameter assignments") }
                target = found
            }
            guard seen[target] == 0 else { throw try failure(assignment, "SV_PARAMETER_DUPLICATE_OVERRIDE", "A parameter has more than one assignment") }
            seen[target] = 1
            if let value {
                let expression: SystemVerilogConstantExpression
                if let scope { expression = try SystemVerilogConstantExpression.prepare(node: value, in: scope, context: &context) }
                else { expression = try SystemVerilogConstantExpression.prepare(node: value, in: parent, context: &context) }
                overrides.append(SystemVerilogParameterOverride(declaration: target, in: child, expression: expression))
            }
        }
    }
}
