public struct LogicDataflowParameter: Sendable, Hashable, Codable {
    public let name: String
    public let type: LogicDataflowType
    public let externalNumericID: UInt64?

    public init(
        name: String,
        type: LogicDataflowType,
        externalNumericID: UInt64? = nil
    ) {
        self.name = name
        self.type = type
        self.externalNumericID = externalNumericID
    }
}
