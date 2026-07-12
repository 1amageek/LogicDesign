import Foundation

public struct GatePin: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var direction: GatePinDirection
    public var netID: String?
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        direction: GatePinDirection,
        netID: String? = nil,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.direction = direction
        self.netID = netID
        self.source = source
    }
}
