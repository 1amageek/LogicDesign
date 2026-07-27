public struct LogicDataflowProcess: Sendable, Hashable, Codable {
    public let name: String
    public let stateElements: [LogicDataflowStateElement]
    public let nodes: [LogicDataflowNode]
    public let nextStateValues: [String]

    public init(
        name: String,
        stateElements: [LogicDataflowStateElement],
        nodes: [LogicDataflowNode],
        nextStateValues: [String]
    ) {
        self.name = name
        self.stateElements = stateElements
        self.nodes = nodes
        self.nextStateValues = nextStateValues
    }
}
