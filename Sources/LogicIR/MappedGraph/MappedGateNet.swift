import CircuiteFoundation
import LogicKernelCore

public struct MappedGateNet: Sendable {
    public enum Driver: Sendable, Equatable {
        case input
        case constant(Bool)
        case instanceOutput(MappedInstanceIndex, LogicCellPinIndex)
    }
    public let id: DesignEntityID
    public let driver: Driver
    public let origin: LogicKernelSourceRange?
    public init(id: DesignEntityID, driver: Driver, origin: LogicKernelSourceRange? = nil) {
        self.id = id; self.driver = driver; self.origin = origin
    }
}
