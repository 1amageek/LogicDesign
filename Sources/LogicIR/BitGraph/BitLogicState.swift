import CircuiteFoundation
import LogicKernelCore

public struct BitLogicState: Sendable, Equatable {
    public let id: DesignEntityID
    public let next: BitNodeIndex
    public let control: BitStateControl
    public let initialValue: Bool?
    public let origin: LogicKernelSourceRange?

    public init(id: DesignEntityID, next: BitNodeIndex, control: BitStateControl,
                initialValue: Bool? = nil, origin: LogicKernelSourceRange? = nil) {
        self.id = id
        self.next = next
        self.control = control
        self.initialValue = initialValue
        self.origin = origin
    }
}
