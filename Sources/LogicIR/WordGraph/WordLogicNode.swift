import CircuiteFoundation
import LogicKernelCore

public struct WordLogicNode: Sendable, Equatable {
    public let id: DesignEntityID
    public let type: WordLogicType
    public let operation: WordLogicOperation
    public let operands: Range<Int>
    public let origin: LogicKernelSourceRange?

    internal init(id: DesignEntityID, type: WordLogicType, operation: WordLogicOperation,
                  operands: Range<Int>, origin: LogicKernelSourceRange?) {
        self.id = id; self.type = type; self.operation = operation
        self.operands = operands; self.origin = origin
    }
}
