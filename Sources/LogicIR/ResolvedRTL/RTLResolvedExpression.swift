import CircuiteFoundation
import LogicKernelCore

public struct RTLResolvedExpression: Sendable {
    public enum Operation: Sendable {
        case read(RTLSignalIndex)
        case constant(LogicFourStateVector)
        case compute(WordLogicOpcode)
        case caseEqual
        case dynamicSelect
    }
    public let id: DesignEntityID
    public let type: WordLogicType
    public let operation: Operation
    public let operands: Range<Int>
    public let origin: LogicKernelSourceRange?
    internal init(id: DesignEntityID, type: WordLogicType, operation: Operation,
                  operands: Range<Int>, origin: LogicKernelSourceRange?) {
        self.id = id; self.type = type; self.operation = operation
        self.operands = operands; self.origin = origin
    }
}
