import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLAssignment: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `target`, `value`, `nonBlocking`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let target = try container.decode(RTLExpression.self, forKey: .`target`)
        let value = try container.decode(RTLExpression.self, forKey: .`value`)
        let nonBlocking = try container.decode(Bool.self, forKey: .`nonBlocking`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, target: target, value: value, nonBlocking: nonBlocking, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(target, forKey: .`target`)
        try container.encode(value, forKey: .`value`)
        try container.encode(nonBlocking, forKey: .`nonBlocking`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
