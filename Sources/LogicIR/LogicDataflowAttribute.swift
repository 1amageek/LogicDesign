public struct LogicDataflowAttribute: Sendable, Hashable, Codable {
    public let name: String
    public let value: LogicDataflowAttributeValue

    public init(name: String, value: LogicDataflowAttributeValue) {
        self.name = name
        self.value = value
    }
}
