public struct LogicDataflowFunction: Sendable, Hashable, Codable {
    public let name: String
    public let parameters: [LogicDataflowParameter]
    public let returnType: LogicDataflowType
    public let nodes: [LogicDataflowNode]
    public let returnValue: String

    public init(
        name: String,
        parameters: [LogicDataflowParameter],
        returnType: LogicDataflowType,
        nodes: [LogicDataflowNode],
        returnValue: String
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.nodes = nodes
        self.returnValue = returnValue
    }
}
