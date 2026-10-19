public struct LogicDataflowStateElement: Sendable, Hashable {
    public let name: String
    public let type: LogicDataflowType
    public let initialValue: LogicDataflowValue

    public init(name: String, type: LogicDataflowType, initialValue: LogicDataflowValue) {
        self.name = name
        self.type = type
        self.initialValue = initialValue
    }
}
