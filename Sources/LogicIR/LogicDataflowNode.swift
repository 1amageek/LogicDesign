public struct LogicDataflowNode: Sendable, Hashable, Codable {
    public let name: String
    public let type: LogicDataflowType
    public let operation: LogicDataflowOperation
    public let externalNumericID: UInt64?

    public init(
        name: String,
        type: LogicDataflowType,
        operation: LogicDataflowOperation,
        externalNumericID: UInt64? = nil
    ) {
        self.name = name
        self.type = type
        self.operation = operation
        self.externalNumericID = externalNumericID
    }
}
