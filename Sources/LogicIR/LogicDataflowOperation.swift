public struct LogicDataflowOperation: Sendable, Hashable, Codable {
    public let kind: LogicDataflowOperationKind
    public let operands: [String]
    public let attributes: [LogicDataflowAttribute]

    public init(
        kind: LogicDataflowOperationKind,
        operands: [String] = [],
        attributes: [LogicDataflowAttribute] = []
    ) {
        self.kind = kind
        self.operands = operands
        self.attributes = attributes
    }
}
