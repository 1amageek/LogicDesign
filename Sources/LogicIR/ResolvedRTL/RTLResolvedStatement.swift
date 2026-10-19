import CircuiteFoundation
import LogicKernelCore

public struct RTLResolvedStatement: Sendable {
    public enum Timing: Sendable { case blocking, nonBlocking }
    public enum Operation: Sendable {
        case assignment(target: RTLSignalIndex, selection: Range<Int>, value: RTLExpressionIndex, timing: Timing)
        case assignmentGroup(children: Range<Int>)
        case block(children: Range<Int>)
        case conditional(condition: RTLExpressionIndex, ifTrue: RTLStatementIndex, ifFalse: RTLStatementIndex?)
        case caseStatement(selector: RTLExpressionIndex, items: Range<Int>, defaultBody: RTLStatementIndex?)
        case empty
    }
    public let id: DesignEntityID
    public let operation: Operation
    public let origin: LogicKernelSourceRange?
    public init(id: DesignEntityID, operation: Operation, origin: LogicKernelSourceRange? = nil) {
        self.id = id; self.operation = operation; self.origin = origin
    }
}
