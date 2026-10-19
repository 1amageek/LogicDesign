import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
package struct SystemVerilogProgramCompiler: ~Copyable {
    struct Module: Equatable { let tree: Int; let node: Int }
    struct Signal { let namespace: UInt64; let declaration: Int; let binding: SystemVerilogSignalBinding }
    struct Port { let name: Int; let declaration: Int; let direction: SystemVerilogSyntaxNode.Direction; let initial: Int? }
    struct Connection { let port: Port; let actual: Int? }

    let trees: [SystemVerilogSyntaxTree]
    let capacity: RTLResolvedCapacity
    let maximumNesting: Int
    var builder: ElaboratedRTLBuilder
    var nextEntityID: UInt64 = 2
    var nextNamespace: UInt64 = 1
    var caseCount = 0
    var depth = 0
    var ancestry: [Module] = []
    var signals: [Signal] = []
    var controls: [(signal: RTLSignalIndex, expression: RTLExpressionIndex)] = []
    var emissionInputs: [RTLExpressionIndex] = []

    package static func compile(_ trees: consuming [SystemVerilogSyntaxTree], top: String,
        capacity: RTLResolvedCapacity, maximumNesting: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> ElaboratedRTL {
        guard !trees.isEmpty, !top.isEmpty, maximumNesting > 0 else { throw .invalidInput("Invalid program elaboration inputs") }
        var modules = 0
        for index in trees.indices {
            try context.charge(.workUnits)
            let sum = modules.addingReportingOverflow(trees[index].modules.count)
            guard !sum.overflow else { throw .invalidInput("Program module count overflow") }
            modules = sum.partialValue
        }
        let bytes = try SystemVerilogConstantEvaluator.bytes(capacity.signals,
            MemoryLayout<Signal>.stride + MemoryLayout<(RTLSignalIndex, RTLExpressionIndex)>.stride)
        let nesting = try SystemVerilogConstantEvaluator.bytes(modules, MemoryLayout<Module>.stride)
        let cacheBytes = bytes.addingReportingOverflow(nesting)
        let sum = cacheBytes.partialValue.addingReportingOverflow(UInt64(MemoryLayout<RTLExpressionIndex>.stride * 3))
        guard !cacheBytes.overflow, !sum.overflow else { throw .invalidInput("Program workspace capacity overflow") }
        let scratch = try context.reserveStorage(byteCount: sum.partialValue)
        let result: ElaboratedRTL
        do throws(LogicKernelError) {
            let builder = try ElaboratedRTLBuilder(topModuleID: entity(1), capacity: capacity, context: &context)
            var run = Self(trees: trees, capacity: capacity, maximumNesting: maximumNesting, builder: builder)
            run.ancestry.reserveCapacity(modules); run.signals.reserveCapacity(capacity.signals)
            run.controls.reserveCapacity(capacity.signals)
            run.emissionInputs.reserveCapacity(3)
            let selected = try run.validateModules(top: top, context: &context)
            let bindings = try SystemVerilogParameterBinder.bind(run.trees[selected.tree], module: selected.node, context: &context)
            let defaults = try SystemVerilogConstantEvaluator.evaluate(bindings, context: &context)
            _ = try run.module(selected, defaults: defaults, parent: nil, instance: nil, context: &context)
            result = try run.builder.finish(context: &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }
    static func entity(_ value: UInt64) throws(LogicKernelError) -> DesignEntityID {
        guard value > 0, value < .max else { throw .invalidInput("Program entity namespace exhausted") }
        do { return try DesignEntityID(rawValue: value) }
        catch { throw .invalidModel("Foundation rejected an admitted entity identifier") }
    }
    mutating func id() throws(LogicKernelError) -> DesignEntityID {
        let result = try Self.entity(nextEntityID); nextEntityID += 1; return result
    }
    mutating func namespace(context: inout LogicKernelContext) throws(LogicKernelError) -> UInt64 {
        guard nextNamespace < .max else { throw .invalidInput("Program namespace exhausted") }
        try context.charge(.expansion)
        let result = nextNamespace; nextNamespace += 1; return result
    }
    mutating func enter(_ node: Int, syntax: borrowing SystemVerilogSyntaxTree,
        context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.charge(.workUnits)
        guard depth < maximumNesting else {
            throw try SystemVerilogConstantScope.failure(node, in: syntax, "SV_ELABORATION_NESTING", "Program nesting exceeds the selected profile")
        }
        depth += 1
    }
    static func origin(_ node: Int, syntax: borrowing SystemVerilogSyntaxTree) throws(LogicKernelError) -> LogicKernelSourceRange {
        let range = try syntax.node(at: node).byteRange
        return try syntax.source.origin(for: range)
    }
    static func failure(_ node: Int, scope: borrowing SystemVerilogSignalScope,
        _ code: String, _ message: String) throws(LogicKernelError) -> LogicKernelError {
        try SystemVerilogConstantScope.failure(node, in: scope.constants.defaults.bindings.syntax, code, message)
    }
    mutating func expression(_ node: Int, scope: borrowing SystemVerilogSignalScope, width: Int? = nil,
        signed: Bool? = nil, context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogResolvedExpression {
        try SystemVerilogExpressionCompiler.compile(node, in: scope, width: width, signed: signed,
            builder: &builder, nextEntityID: &nextEntityID, context: &context)
    }
    mutating func emit(_ operation: RTLResolvedExpression.Operation, type: WordLogicType,
        a: RTLExpressionIndex? = nil, b: RTLExpressionIndex? = nil, node: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogResolvedExpression {
        emissionInputs.removeAll(keepingCapacity: true)
        if let a { emissionInputs.append(a) }; if let b { emissionInputs.append(b) }
        let supplied = emissionInputs
        let identity = try id()
        let index = try builder.addExpression(id: identity, type: type, operation: operation, inputs: supplied,
            origin: Self.origin(node, syntax: scope.constants.defaults.bindings.syntax), context: &context)
        return SystemVerilogResolvedExpression(index: index, type: type)
    }
    mutating func truth(_ input: SystemVerilogResolvedExpression, node: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> RTLExpressionIndex {
        let scalar = WordLogicType(width: try LogicBitWidth(1))
        if input.type == scalar { return input.index }
        return try emit(.compute(.reduceOr), type: scalar, a: input.index, node: node, scope: scope, context: &context).index
    }
    mutating func empty(_ node: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        try builder.addStatement(RTLResolvedStatement(id: id(), operation: .empty,
            origin: Self.origin(node, syntax: scope.constants.defaults.bindings.syntax)), context: &context)
    }
    mutating func block(_ body: borrowing [RTLStatementIndex], node: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        try builder.addBlock(id: id(), body: body,
            origin: Self.origin(node, syntax: scope.constants.defaults.bindings.syntax), context: &context)
    }
}
