import CircuiteFoundation
import LogicKernelCore

public struct MappedGateInstance: Sendable {
    public let id: DesignEntityID
    public let cell: LogicCellIndex
    public let pins: Range<Int>
    public let stateID: DesignEntityID?
    public let initialValue: Bool?

    /// Current cell definitions provide no physical power-up mechanism for a specified initial value.
    public func requirePhysicalStartupRealization() throws(LogicKernelError) {
        if let initial = initialValue {
            throw .unsupported("Mapped instance \(id.rawValue) demands initial state \(initial ? 1 : 0); the cell has no physical startup realization")
        }
    }
    public let origin: LogicKernelSourceRange?

    internal init(id: DesignEntityID, cell: LogicCellIndex, pins: Range<Int>, stateID: DesignEntityID?,
                  initialValue: Bool?, origin: LogicKernelSourceRange?) {
        self.id = id; self.cell = cell; self.pins = pins; self.stateID = stateID
        self.initialValue = initialValue; self.origin = origin
    }
}
