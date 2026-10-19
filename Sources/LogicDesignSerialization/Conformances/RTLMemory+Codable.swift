import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLMemory: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `name`, `elementRange`, `elementRangeExpression`, `addressRange`, `addressRangeExpression`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let name = try container.decode(String.self, forKey: .`name`)
        let elementRange = try container.decodeIfPresent(LogicRange.self, forKey: .`elementRange`)
        let elementRangeExpression = try container.decodeIfPresent(RTLRangeExpression.self, forKey: .`elementRangeExpression`)
        let addressRange = try container.decode(LogicRange.self, forKey: .`addressRange`)
        let addressRangeExpression = try container.decodeIfPresent(RTLRangeExpression.self, forKey: .`addressRangeExpression`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, name: name, elementRange: elementRange, addressRange: addressRange, elementRangeExpression: elementRangeExpression, addressRangeExpression: addressRangeExpression, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(name, forKey: .`name`)
        try container.encodeIfPresent(elementRange, forKey: .`elementRange`)
        try container.encodeIfPresent(elementRangeExpression, forKey: .`elementRangeExpression`)
        try container.encode(addressRange, forKey: .`addressRange`)
        try container.encodeIfPresent(addressRangeExpression, forKey: .`addressRangeExpression`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
