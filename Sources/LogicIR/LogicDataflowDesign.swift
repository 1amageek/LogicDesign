public struct LogicDataflowDesign: Sendable, Hashable, Codable {
    public let packageName: String
    public let topEntityName: String?
    public let functions: [LogicDataflowFunction]
    public let processes: [LogicDataflowProcess]
    public let channels: [LogicDataflowChannel]

    public init(
        packageName: String,
        topEntityName: String? = nil,
        functions: [LogicDataflowFunction] = [],
        processes: [LogicDataflowProcess] = [],
        channels: [LogicDataflowChannel] = []
    ) {
        self.packageName = packageName
        self.topEntityName = topEntityName
        self.functions = functions
        self.processes = processes
        self.channels = channels
    }
}
