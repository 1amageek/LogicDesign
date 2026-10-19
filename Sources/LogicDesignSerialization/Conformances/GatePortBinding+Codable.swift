import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension GatePortBinding: Codable {
    private enum CodingKeys: String, CodingKey { case `portID`, `netID` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let portID = try container.decode(String.self, forKey: .`portID`)
        let netID = try container.decode(String.self, forKey: .`netID`)
        self.init(portID: portID, netID: netID)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(portID, forKey: .`portID`)
        try container.encode(netID, forKey: .`netID`)
    }
}
