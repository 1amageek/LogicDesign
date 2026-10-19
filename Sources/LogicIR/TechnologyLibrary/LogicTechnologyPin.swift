import CircuiteFoundation

public struct LogicTechnologyPin: Sendable {
    public enum Direction: Sendable { case input, output }
    public let id: DesignEntityID
    public let name: String
    public let direction: Direction
    public let function: LogicBooleanFunction?

    public init(id: DesignEntityID, name: String, direction: Direction, function: LogicBooleanFunction? = nil) {
        self.id = id; self.name = name; self.direction = direction; self.function = function
    }
}
