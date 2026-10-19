import LogicIR
import LogicKernelCore

package struct SystemVerilogConstantScope: Sendable {
    internal final class Identity: Sendable {}
    internal final class Storage: Sendable {
        let identity: Identity
        let parent: SystemVerilogConstantScope?
        let entries: [SystemVerilogScopeEntry]
        let children: [Int]
        init(parent: SystemVerilogConstantScope?, entries: consuming [SystemVerilogScopeEntry],
             children: consuming [Int], identity: Identity?) {
            self.identity = identity ?? Identity()
            self.parent = parent; self.entries = entries; self.children = children
        }
    }
    package let defaults: SystemVerilogParameterDefaults
    package let container: Int
    internal let storage: Storage
    internal init(defaults: SystemVerilogParameterDefaults, container: Int,
                  parent: SystemVerilogConstantScope?, entries: consuming [SystemVerilogScopeEntry],
                  children: consuming [Int], identity: Identity? = nil) {
        self.defaults = defaults; self.container = container
        storage = Storage(parent: parent, entries: entries, children: children, identity: identity)
    }
    @available(macOS 26.0, *)
    package static func module(_ defaults: borrowing SystemVerilogParameterDefaults,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try Self.build(defaults: defaults, container: defaults.bindings.module,
            parent: nil, iteration: nil, context: &context)
    }
    @available(macOS 26.0, *)
    package borrowing func entering(_ container: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Self {
        try requireChild(container, context: &context)
        switch try defaults.bindings.syntax.node(at: container).kind {
        case .forStatement, .generateFor:
            throw .invalidInput("Entering a loop requires an explicit frozen iteration value")
        default: break
        }
        return try Self.build(defaults: defaults, container: container,
            parent: copy self, iteration: nil, context: &context)
    }
    @available(macOS 26.0, *)
    package borrowing func iteration(of loop: Int, value: borrowing LogicFourStateVector,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try requireChild(loop, context: &context)
        return try Self.build(defaults: defaults, container: loop,
            parent: copy self, iteration: copy value, context: &context)
    }
    @available(macOS 26.0, *)
    internal borrowing func requireChild(_ child: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        for entry in storage.children {
            try context.charge(.workUnits)
            if entry == child { return }
        }
        throw .invalidInput("Syntax is not a direct lexical child of the supplied scope")
    }
    @available(macOS 26.0, *)
    package borrowing func owns(_ node: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        try context.checkpoint()
        let syntax = defaults.bindings.syntax
        let candidate = try syntax.node(at: node).byteRange
        let range = try syntax.node(at: container).byteRange
        guard node <= container, candidate.lowerBound >= range.lowerBound,
              candidate.upperBound <= range.upperBound else { return false }
        for child in storage.children {
            try context.charge(.workUnits)
            let boundary = try syntax.node(at: child).byteRange
            if node <= child && candidate.lowerBound >= boundary.lowerBound && candidate.upperBound <= boundary.upperBound {
                return false
            }
        }
        return true
    }
    @available(macOS 26.0, *)
    internal borrowing func lookup(_ symbol: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogScopeEntry? {
        var current: Self? = copy self
        while let scope = current {
            for entry in scope.storage.entries {
                try context.charge(.workUnits)
                if entry.symbol == symbol { return entry }
            }
            current = scope.storage.parent
        }
        return nil
    }
}
