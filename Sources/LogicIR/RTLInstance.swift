import Foundation

public struct RTLInstance: Sendable, Hashable, Codable {
    public var id: String
    public var moduleName: String
    public var instanceName: String
    public var parameterOverrides: [String: Int64]
    public var connections: [RTLPortConnection]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        moduleName: String,
        instanceName: String,
        parameterOverrides: [String: Int64] = [:],
        connections: [RTLPortConnection] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.moduleName = moduleName
        self.instanceName = instanceName
        self.parameterOverrides = parameterOverrides
        self.connections = connections
        self.source = source
    }
}
