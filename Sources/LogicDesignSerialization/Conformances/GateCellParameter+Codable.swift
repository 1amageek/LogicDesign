import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension GateCellParameter: Codable {
    private enum CodingKeys: String, CodingKey { case `name`, `value` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .`name`)
        let value = try container.decode(GateCellParameterValue.self, forKey: .`value`)
        self.init(name: name, value: value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .`name`)
        try container.encode(value, forKey: .`value`)
    }
}
