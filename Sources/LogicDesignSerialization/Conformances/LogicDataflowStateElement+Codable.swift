import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowStateElement: Codable {
    private enum CodingKeys: String, CodingKey { case `name`, `type`, `initialValue` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .`name`)
        let type = try container.decode(LogicDataflowType.self, forKey: .`type`)
        let initialValue = try container.decode(LogicDataflowValue.self, forKey: .`initialValue`)
        self.init(name: name, type: type, initialValue: initialValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .`name`)
        try container.encode(type, forKey: .`type`)
        try container.encode(initialValue, forKey: .`initialValue`)
    }
}
