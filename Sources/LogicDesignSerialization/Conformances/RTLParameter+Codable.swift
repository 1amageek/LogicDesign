import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLParameter: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `name`, `value`, `defaultExpression`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let name = try container.decode(String.self, forKey: .`name`)
        let value = try container.decode(Int64.self, forKey: .`value`)
        let defaultExpression = try container.decodeIfPresent(RTLExpression.self, forKey: .`defaultExpression`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, name: name, value: value, defaultExpression: defaultExpression, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(name, forKey: .`name`)
        try container.encode(value, forKey: .`value`)
        try container.encodeIfPresent(defaultExpression, forKey: .`defaultExpression`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
