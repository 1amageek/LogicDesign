import CircuiteFoundation
import LogicIR
import LogicKernelCore

package struct SystemVerilogParameterBinder: ~Copyable {
    internal let syntax: SystemVerilogSyntaxTree
    internal let module: Int
    internal var declarations: [Int] = []
    internal var references: [Int]
    internal var symbols: [Int]
    internal var visited: [UInt8]
    internal var pending: [Int] = []

    package static func bind(_ syntax: borrowing SystemVerilogSyntaxTree, module: Int,
                             context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogParameterBindings {
        try context.checkpoint()
        guard case .module(_, let parameters, _, let items, _) = try syntax.node(at: module).kind else {
            throw .invalidInput("Parameter binding requires a module node")
        }
        let nodeBytes = try byteCount(syntax.nodeCount, stride: MemoryLayout<Int>.stride)
        let symbolBytes = try byteCount(syntax.symbolCount, stride: MemoryLayout<Int>.stride)
        let published = try sum(try sum(nodeBytes, nodeBytes), symbolBytes)
        let scratchBytes = try sum(nodeBytes, try byteCount(syntax.nodeCount, stride: MemoryLayout<UInt8>.stride))
        try context.require(.managedStorageBytes, amount: try sum(published, scratchBytes))
        _ = try context.reserveStorage(byteCount: published)
        let scratch = try context.reserveStorage(byteCount: scratchBytes)
        let result: SystemVerilogParameterBindings
        do throws(LogicKernelError) {
            var binder = SystemVerilogParameterBinder(syntax: copy syntax, module: module,
                references: [Int](repeating: -1, count: syntax.nodeCount),
                symbols: [Int](repeating: -1, count: syntax.symbolCount),
                visited: [UInt8](repeating: 0, count: syntax.nodeCount))
            binder.declarations.reserveCapacity(syntax.nodeCount)
            binder.pending.reserveCapacity(syntax.nodeCount)
            try binder.enqueue(items, parent: module, context: &context)
            try binder.enqueue(parameters, parent: module, context: &context)
            try binder.collect(context: &context)
            for index in 0..<binder.declarations.count {
                try binder.bindDeclaration(binder.declarations[index], context: &context)
            }
            result = binder.publish()
        } catch {
            try context.releaseStorage(scratch)
            throw error
        }
        try context.releaseStorage(scratch)
        return result
    }

    private static func byteCount(_ count: Int, stride: Int) throws(LogicKernelError) -> UInt64 {
        let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
        guard !bytes.overflow else { throw .invalidInput("Parameter table storage overflow") }
        return bytes.partialValue
    }
    private static func sum(_ lhs: UInt64, _ rhs: UInt64) throws(LogicKernelError) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw .invalidInput("Parameter table storage overflow") }
        return result.partialValue
    }
    internal consuming func publish() -> SystemVerilogParameterBindings {
        SystemVerilogParameterBindings(syntax: syntax, module: module, declarations: declarations,
                                       references: references, symbols: symbols)
    }
    internal borrowing func failure(_ code: String, at node: Int, _ message: String)
        throws(LogicKernelError) -> LogicKernelError {
        let range = try syntax.node(at: node).byteRange
        return .sourceFailure(code: .trusted(code), source: try syntax.source.origin(for: range), message: message)
    }
    internal mutating func enqueue(_ node: Int, parent: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        try context.charge(.workUnits)
        guard node >= 0 && node < parent && parent < syntax.nodeCount else {
            throw .invalidModel("Parameter syntax references must point to earlier nodes")
        }
        guard pending.count < syntax.nodeCount else {
            throw .invalidModel("Parameter traversal exceeds the syntax node capacity")
        }
        pending.append(node)
    }
    internal mutating func enqueue(_ range: Range<Int>, parent: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        for child in range.reversed() { try enqueue(syntax.child(at: child), parent: parent, context: &context) }
    }
    internal mutating func collect(context: inout LogicKernelContext) throws(LogicKernelError) {
        while let index = pending.popLast() {
            try context.charge(.workUnits)
            switch try syntax.node(at: index).kind {
            case .group(let children), .generateRegion(let children):
                try enqueue(children, parent: index, context: &context)
            case .declaration(let kind, let name, _, let initial) where kind == .parameter || kind == .localParameter:
                guard symbols.indices.contains(name) else { throw .invalidModel("Parameter name is outside the syntax symbol table") }
                guard symbols[name] == -1 else {
                    throw try failure("SV_PARAMETER_DUPLICATE", at: index, "Duplicate parameter in the same module scope")
                }
                guard initial != nil else {
                    throw try failure("SV_PARAMETER_MISSING_DEFAULT", at: index, "Default binding requires a parameter initializer")
                }
                try context.charge(.expansion)
                declarations.append(index); symbols[name] = index
            default: break
            }
        }
    }
}
