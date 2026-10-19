import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowNode: Codable {
    private enum CodingKeys: String, CodingKey { case `name`, `type`, `operation`, `externalNumericID` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .`name`)
        let type = try container.decode(LogicDataflowType.self, forKey: .`type`)
        let operation = try container.decode(LogicDataflowOperation.self, forKey: .`operation`)
        let externalNumericID = try container.decodeIfPresent(UInt64.self, forKey: .`externalNumericID`)
        self.init(name: name, type: type, operation: operation, externalNumericID: externalNumericID)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .`name`)
        try container.encode(type, forKey: .`type`)
        try container.encode(operation, forKey: .`operation`)
        try container.encodeIfPresent(externalNumericID, forKey: .`externalNumericID`)
    }
}
