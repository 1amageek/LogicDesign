internal struct RTLResolvedTables: Sendable {
    let signals: [RTLResolvedSignal]
    let expressions: [RTLResolvedExpression]
    let operands: [RTLExpressionIndex]
    let statements: [RTLResolvedStatement]
    let children: [RTLStatementIndex]
    let caseItems: [RTLResolvedCaseItem]
    let caseMatches: [RTLExpressionIndex]
    let ports: [RTLResolvedPort]
    let processes: [RTLResolvedProcess]
    init(signals: consuming [RTLResolvedSignal], expressions: consuming [RTLResolvedExpression],
         operands: consuming [RTLExpressionIndex], statements: consuming [RTLResolvedStatement],
         children: consuming [RTLStatementIndex], caseItems: consuming [RTLResolvedCaseItem],
         caseMatches: consuming [RTLExpressionIndex], ports: consuming [RTLResolvedPort],
         processes: consuming [RTLResolvedProcess]) {
        self.signals = signals; self.expressions = expressions; self.operands = operands
        self.statements = statements; self.children = children; self.caseItems = caseItems
        self.caseMatches = caseMatches; self.ports = ports; self.processes = processes
    }
}
