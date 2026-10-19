import LogicKernelCore

public struct RTLResolvedCapacity: Sendable {
    public let signals: Int
    public let expressions: Int
    public let operands: Int
    public let statements: Int
    public let children: Int
    public let caseItems: Int
    public let caseMatches: Int
    public let ports: Int
    public let processes: Int
    public init(signals: Int, expressions: Int, operands: Int, statements: Int, children: Int,
                caseItems: Int, caseMatches: Int, ports: Int, processes: Int) throws(LogicKernelError) {
        guard [signals, expressions, operands, statements, children, caseItems, caseMatches, ports, processes].allSatisfy({ $0 >= 0 }) else {
            throw .invalidInput("Negative resolved RTL capacity")
        }
        self.signals = signals; self.expressions = expressions; self.operands = operands
        self.statements = statements; self.children = children; self.caseItems = caseItems
        self.caseMatches = caseMatches; self.ports = ports; self.processes = processes
    }
    internal func storageBytes() throws(LogicKernelError) -> UInt64 {
        var bytes: UInt64 = 0
        for (count, stride) in [(signals, MemoryLayout<RTLResolvedSignal>.stride),
                                (expressions, MemoryLayout<RTLResolvedExpression>.stride + MemoryLayout<RTLExpressionIndex>.stride),
                                (operands, MemoryLayout<RTLExpressionIndex>.stride),
                                (statements, MemoryLayout<RTLResolvedStatement>.stride),
                                (children, MemoryLayout<RTLStatementIndex>.stride),
                                (caseItems, MemoryLayout<RTLResolvedCaseItem>.stride),
                                (caseMatches, MemoryLayout<RTLExpressionIndex>.stride),
                                (ports, MemoryLayout<RTLResolvedPort>.stride),
                                (processes, MemoryLayout<RTLResolvedProcess>.stride)] {
            let size = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let sum = bytes.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !sum.overflow else { throw .invalidInput("Resolved RTL storage overflow") }
            bytes = sum.partialValue
        }
        return bytes
    }
}
