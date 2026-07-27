public struct LogicDataflowFIFOConfiguration: Sendable, Hashable, Codable {
    public let depth: Int?
    public let bypass: Bool?
    public let implementationName: String?
    public let inputFlopKind: LogicDataflowFlopKind?
    public let outputFlopKind: LogicDataflowFlopKind?

    public init(
        depth: Int? = nil,
        bypass: Bool? = nil,
        implementationName: String? = nil,
        inputFlopKind: LogicDataflowFlopKind? = nil,
        outputFlopKind: LogicDataflowFlopKind? = nil
    ) {
        self.depth = depth
        self.bypass = bypass
        self.implementationName = implementationName
        self.inputFlopKind = inputFlopKind
        self.outputFlopKind = outputFlopKind
    }
}
