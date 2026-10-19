import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension GatePin: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `name`, `direction`, `netID`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let name = try container.decode(String.self, forKey: .`name`)
        let direction = try container.decode(GatePinDirection.self, forKey: .`direction`)
        let netID = try container.decodeIfPresent(String.self, forKey: .`netID`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, name: name, direction: direction, netID: netID, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(name, forKey: .`name`)
        try container.encode(direction, forKey: .`direction`)
        try container.encodeIfPresent(netID, forKey: .`netID`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
