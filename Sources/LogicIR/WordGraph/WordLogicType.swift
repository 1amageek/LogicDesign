public struct WordLogicType: Sendable, Hashable {
    public let width: LogicBitWidth
    public let isSigned: Bool
    public init(width: LogicBitWidth, isSigned: Bool = false) {
        self.width = width; self.isSigned = isSigned
    }
}
