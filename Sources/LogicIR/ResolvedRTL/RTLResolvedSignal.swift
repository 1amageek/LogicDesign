import CircuiteFoundation
import LogicKernelCore

public struct RTLResolvedSignal: Sendable {
    public enum ValueDomain: Sendable { case twoState, fourState }
    public enum StorageKind: Sendable { case variable, net }
    public let id: DesignEntityID
    public let type: WordLogicType
    public let valueDomain: ValueDomain
    public let storage: StorageKind
    public let isInput: Bool
    public let initialValue: LogicFourStateVector?
    public let origin: LogicKernelSourceRange?
    public var defaultInitialBit: LogicBit {
        if valueDomain == .twoState { return .zero }
        return storage == .net ? .highImpedance : .unknown
    }
    public init(id: DesignEntityID, type: WordLogicType, isInput: Bool = false,
                initialValue: LogicFourStateVector? = nil, origin: LogicKernelSourceRange? = nil,
                valueDomain: ValueDomain = .fourState, storage: StorageKind = .variable) {
        self.id = id; self.type = type; self.isInput = isInput
        self.valueDomain = valueDomain; self.storage = storage
        self.initialValue = initialValue; self.origin = origin
    }
}
