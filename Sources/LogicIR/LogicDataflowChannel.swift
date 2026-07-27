public struct LogicDataflowChannel: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case streaming
        case singleValue
    }

    public enum Operations: String, Sendable, Hashable, Codable {
        case sendOnly
        case receiveOnly
        case sendReceive
    }

    public enum FlowControl: String, Sendable, Hashable, Codable {
        case none
        case readyValid
    }

    public let id: UInt64
    public let name: String
    public let type: LogicDataflowType
    public let kind: Kind
    public let operations: Operations
    public let flowControl: FlowControl?
    public let initialValues: [LogicDataflowValue]
    public let strictness: LogicDataflowChannelStrictness?
    public let fifoConfiguration: LogicDataflowFIFOConfiguration?

    public init(
        id: UInt64,
        name: String,
        type: LogicDataflowType,
        kind: Kind,
        operations: Operations,
        flowControl: FlowControl? = nil,
        initialValues: [LogicDataflowValue] = [],
        strictness: LogicDataflowChannelStrictness? = nil,
        fifoConfiguration: LogicDataflowFIFOConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.kind = kind
        self.operations = operations
        self.flowControl = flowControl
        self.initialValues = initialValues
        self.strictness = strictness
        self.fifoConfiguration = fifoConfiguration
    }
}
