import CircuiteFoundation

public struct ElaboratedRTL: Sendable {
    public static let schemaVersion = 1
    internal final class Storage: Sendable {
        let topModuleID: DesignEntityID
        let tables: RTLResolvedTables
        let expressionOrder: [RTLExpressionIndex]
        init(topModuleID: DesignEntityID, tables: consuming RTLResolvedTables, expressionOrder: consuming [RTLExpressionIndex]) {
            self.topModuleID = topModuleID; self.tables = tables; self.expressionOrder = expressionOrder
        }
    }
    internal let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var topModuleID: DesignEntityID { storage.topModuleID }
    public var signalCount: Int { storage.tables.signals.count }
    public var expressionCount: Int { storage.tables.expressions.count }
    public var statementCount: Int { storage.tables.statements.count }
    public var processCount: Int { storage.tables.processes.count }
    public var portCount: Int { storage.tables.ports.count }

    @available(macOS 26.0, *)
    public borrowing func withExpressions<Result, Failure: Error>(
        _ body: (borrowing Span<RTLResolvedExpression>, borrowing Span<RTLExpressionIndex>,
                 borrowing Span<RTLExpressionIndex>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let expressions = owner.tables.expressions
        let operands = owner.tables.operands; let order = owner.expressionOrder
        defer { withExtendedLifetime(owner) {} }
        return try body(expressions.isEmpty ? Span() : expressions.span, operands.isEmpty ? Span() : operands.span,
                        order.isEmpty ? Span() : order.span)
    }
    @available(macOS 26.0, *)
    public borrowing func withProgram<Result, Failure: Error>(
        _ body: (borrowing Span<RTLResolvedSignal>, borrowing Span<RTLResolvedStatement>, borrowing Span<RTLStatementIndex>,
                 borrowing Span<RTLResolvedCaseItem>, borrowing Span<RTLExpressionIndex>, borrowing Span<RTLResolvedPort>,
                 borrowing Span<RTLResolvedProcess>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let signals = owner.tables.signals; let statements = owner.tables.statements; let children = owner.tables.children
        let items = owner.tables.caseItems; let matches = owner.tables.caseMatches; let ports = owner.tables.ports; let processes = owner.tables.processes
        defer { withExtendedLifetime(owner) {} }
        return try body(signals.isEmpty ? Span() : signals.span, statements.isEmpty ? Span() : statements.span,
                        children.isEmpty ? Span() : children.span, items.isEmpty ? Span() : items.span,
                        matches.isEmpty ? Span() : matches.span, ports.isEmpty ? Span() : ports.span,
                        processes.isEmpty ? Span() : processes.span)
    }
}
