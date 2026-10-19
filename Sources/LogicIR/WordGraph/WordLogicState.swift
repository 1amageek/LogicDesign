import CircuiteFoundation
import LogicKernelCore

public struct WordLogicState: Sendable, Equatable {
    public let id: DesignEntityID
    public let next: WordNodeIndex
    public let control: WordStateControl
    public let initialValue: LogicFourStateVector?
    public let origin: LogicKernelSourceRange?
    public init(id: DesignEntityID, next: WordNodeIndex, control: WordStateControl,
                initialValue: LogicFourStateVector? = nil, origin: LogicKernelSourceRange? = nil) {
        self.id = id; self.next = next; self.control = control
        self.initialValue = initialValue; self.origin = origin
    }
}
