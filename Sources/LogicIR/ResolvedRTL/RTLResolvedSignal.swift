import CircuiteFoundation
import LogicKernelCore

public struct RTLResolvedSignal: Sendable {
    public let id: DesignEntityID
    public let type: WordLogicType
    public let isInput: Bool
    public let initialValue: LogicFourStateVector?
    public let origin: LogicKernelSourceRange?
    public init(id: DesignEntityID, type: WordLogicType, isInput: Bool = false,
                initialValue: LogicFourStateVector? = nil, origin: LogicKernelSourceRange? = nil) {
        self.id = id; self.type = type; self.isInput = isInput
        self.initialValue = initialValue; self.origin = origin
    }
}
