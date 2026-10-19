import CircuiteFoundation

public struct RTLResolvedPort: Sendable {
    public let id: DesignEntityID
    public let name: String
    public let direction: BitLogicPort.Direction
    public let signal: RTLSignalIndex
    public init(id: DesignEntityID, name: String, direction: BitLogicPort.Direction, signal: RTLSignalIndex) {
        self.id = id; self.name = name; self.direction = direction; self.signal = signal
    }
}
