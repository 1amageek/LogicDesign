import CircuiteFoundation
import LogicKernelCore

public struct ElaboratedRTLBuilder: ~Copyable {
    private let topModuleID: DesignEntityID
    private let capacity: RTLResolvedCapacity
    private var signals: [RTLResolvedSignal] = []
    private var expressions: [RTLResolvedExpression] = []
    private var operands: [RTLExpressionIndex] = []
    private var statements: [RTLResolvedStatement] = []
    private var children: [RTLStatementIndex] = []
    private var caseItems: [RTLResolvedCaseItem] = []
    private var caseMatches: [RTLExpressionIndex] = []
    private var ports: [RTLResolvedPort] = []
    private var processes: [RTLResolvedProcess] = []

    public init(topModuleID: DesignEntityID, capacity: RTLResolvedCapacity, context: inout LogicKernelContext) throws(LogicKernelError) {
        var nodes: UInt64 = 0
        for count in [capacity.signals, capacity.expressions, capacity.statements, capacity.processes] {
            let sum = nodes.addingReportingOverflow(UInt64(count))
            guard !sum.overflow else { throw .invalidInput("Resolved node capacity overflow") }
            nodes = sum.partialValue
        }
        try context.require(.nodes, amount: nodes)
        _ = try context.reserveStorage(byteCount: capacity.storageBytes())
        self.topModuleID = topModuleID; self.capacity = capacity
        signals.reserveCapacity(capacity.signals); expressions.reserveCapacity(capacity.expressions)
        operands.reserveCapacity(capacity.operands); statements.reserveCapacity(capacity.statements)
        children.reserveCapacity(capacity.children); caseItems.reserveCapacity(capacity.caseItems)
        caseMatches.reserveCapacity(capacity.caseMatches); ports.reserveCapacity(capacity.ports)
        processes.reserveCapacity(capacity.processes)
    }

    public mutating func addSignal(_ signal: RTLResolvedSignal, context: inout LogicKernelContext)
        throws(LogicKernelError) -> RTLSignalIndex {
        guard signals.count < capacity.signals else { throw .invalidInput("Resolved signal capacity exhausted") }
        try context.observeBitWidth(UInt64(signal.type.width.value))
        try context.charge(.expansion, amount: UInt64(signal.type.width.value))
        try context.charge(.nodes)
        let index = RTLSignalIndex(signals.count); signals.append(signal); return index
    }

    public mutating func addExpression(id: DesignEntityID, type: WordLogicType, operation: RTLResolvedExpression.Operation,
                                      inputs: borrowing [RTLExpressionIndex] = [], origin: LogicKernelSourceRange? = nil,
                                      context: inout LogicKernelContext) throws(LogicKernelError) -> RTLExpressionIndex {
        guard expressions.count < capacity.expressions, inputs.count <= capacity.operands - operands.count else {
            throw .invalidInput("Resolved expression capacity exhausted")
        }
        try context.observeBitWidth(UInt64(type.width.value))
        try context.charge(.nodes); try context.charge(.edges, amount: UInt64(inputs.count))
        let index = RTLExpressionIndex(expressions.count); let start = operands.count
        for offset in inputs.indices { operands.append(inputs[offset]) }
        expressions.append(RTLResolvedExpression(id: id, type: type, operation: operation,
            operands: start..<operands.count, origin: origin))
        return index
    }

    public mutating func addStatement(_ statement: RTLResolvedStatement, context: inout LogicKernelContext)
        throws(LogicKernelError) -> RTLStatementIndex {
        guard statements.count < capacity.statements else { throw .invalidInput("Resolved statement capacity exhausted") }
        let edges: UInt64
        switch statement.operation {
        case .assignment: edges = 2
        case .conditional(_, _, let otherwise): edges = otherwise == nil ? 2 : 3
        case .caseStatement(_, _, let fallback): edges = fallback == nil ? 1 : 2
        case .block, .assignmentGroup, .empty: edges = 0
        }
        try context.charge(.nodes); try context.charge(.edges, amount: edges)
        let index = RTLStatementIndex(statements.count); statements.append(statement); return index
    }

    public mutating func addBlock(id: DesignEntityID, body: borrowing [RTLStatementIndex], origin: LogicKernelSourceRange? = nil,
                                 context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        try addCompound(id: id, body: body, atomic: false, origin: origin, context: &context)
    }

    public mutating func addAssignmentGroup(id: DesignEntityID, body: borrowing [RTLStatementIndex],
        origin: LogicKernelSourceRange? = nil, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        try addCompound(id: id, body: body, atomic: true, origin: origin, context: &context)
    }

    private mutating func addCompound(id: DesignEntityID, body: borrowing [RTLStatementIndex], atomic: Bool,
        origin: LogicKernelSourceRange?, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        guard statements.count < capacity.statements, body.count <= capacity.children - children.count else {
            throw .invalidInput("Resolved block capacity exhausted")
        }
        try context.charge(.nodes); try context.charge(.edges, amount: UInt64(body.count))
        let start = children.count; let index = RTLStatementIndex(statements.count)
        for offset in body.indices { children.append(body[offset]) }
        statements.append(RTLResolvedStatement(id: id, operation: atomic ? .assignmentGroup(children: start..<children.count) : .block(children: start..<children.count), origin: origin))
        return index
    }

    public mutating func addCaseItem<Matches: RandomAccessCollection>(matches: borrowing Matches, body: RTLStatementIndex,
                                    origin: LogicKernelSourceRange? = nil, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int where Matches.Element == RTLExpressionIndex {
        guard caseItems.count < capacity.caseItems, !matches.isEmpty,
              matches.count <= capacity.caseMatches - caseMatches.count else { throw .invalidInput("Resolved case capacity exhausted") }
        try context.charge(.expansion); try context.charge(.edges, amount: UInt64(matches.count) + 1)
        let start = caseMatches.count; let index = caseItems.count
        for offset in matches.indices { caseMatches.append(matches[offset]) }
        caseItems.append(RTLResolvedCaseItem(matches: start..<caseMatches.count, body: body, origin: origin))
        return index
    }

    public mutating func addPort(_ port: RTLResolvedPort, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard ports.count < capacity.ports else { throw .invalidInput("Resolved port capacity exhausted") }
        _ = try context.reserveStorage(byteCount: UInt64(port.name.utf8.count))
        try context.charge(.edges); ports.append(port)
    }

    public mutating func addProcess(_ process: RTLResolvedProcess, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard processes.count < capacity.processes else { throw .invalidInput("Resolved process capacity exhausted") }
        var edges: UInt64 = 1
        if case .flipFlop(_, _, let reset) = process.control { edges += reset == nil ? 1 : 2 }
        try context.charge(.nodes); try context.charge(.edges, amount: edges); processes.append(process)
    }

    public consuming func finish(context: inout LogicKernelContext) throws(LogicKernelError) -> ElaboratedRTL {
        let tables = RTLResolvedTables(signals: signals, expressions: expressions, operands: operands,
            statements: statements, children: children, caseItems: caseItems, caseMatches: caseMatches,
            ports: ports, processes: processes)
        let order = try RTLResolvedValidation.validate(tables, context: &context)
        return ElaboratedRTL(storage: ElaboratedRTL.Storage(topModuleID: topModuleID, tables: tables, expressionOrder: order))
    }
}
