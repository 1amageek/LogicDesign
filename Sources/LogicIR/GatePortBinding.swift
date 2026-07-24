import Foundation

public struct GatePortBinding: Sendable, Hashable, Codable {
    public var portID: String
    public var netID: String

    public init(portID: String, netID: String) {
        self.portID = portID
        self.netID = netID
    }
}
