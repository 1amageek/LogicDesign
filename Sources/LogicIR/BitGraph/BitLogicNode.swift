import CircuiteFoundation
import LogicKernelCore

public struct BitLogicNode: Sendable, Equatable {
    public let id: DesignEntityID
    public let operation: BitOperation
    public let operands: Range<Int>
    public let origin: LogicKernelSourceRange?

    internal init(id: DesignEntityID, operation: BitOperation, operands: Range<Int>, origin: LogicKernelSourceRange?) {
        self.id = id
        self.operation = operation
        self.operands = operands
        self.origin = origin
    }
}
