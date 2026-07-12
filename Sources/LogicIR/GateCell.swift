import Foundation

public struct GateCell: Sendable, Hashable, Codable {
    public var id: String
    public var type: String
    public var instanceName: String
    public var pins: [GatePin]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        type: String,
        instanceName: String,
        pins: [GatePin] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.type = type
        self.instanceName = instanceName
        self.pins = pins
        self.source = source
    }
}
