import CircuiteFoundation

public struct WordLogicPort: Sendable, Equatable {
    public let id: DesignEntityID
    public let direction: BitLogicPort.Direction
    public let value: WordNodeIndex
    public init(id: DesignEntityID, direction: BitLogicPort.Direction, value: WordNodeIndex) {
        self.id = id; self.direction = direction; self.value = value
    }
}
