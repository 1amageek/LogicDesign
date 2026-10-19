import CircuiteFoundation

public struct MappedGatePort: Sendable {
    public enum Direction: Sendable { case input, output }
    public let id: DesignEntityID
    public let direction: Direction
    public let bits: Range<Int>
    internal init(id: DesignEntityID, direction: Direction, bits: Range<Int>) {
        self.id = id; self.direction = direction; self.bits = bits
    }
}
